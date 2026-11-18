import AppKit
import EditorCore
import Foundation
import Neon
import SwiftTreeSitterLayer

/// The parser/cache lifetime behind one mounted large-Markdown editor.
///
/// The storage gate calls `didEdit` for every actual character mutation.
/// Parsing starts only after that synchronous callback returns; publication
/// requires the ticket captured at that exact storage generation. This type
/// does not paint or replace the existing large-file fallback by itself.
@MainActor
final class MarkdownViewportSession {
    typealias SnapshotParser = @Sendable (String, GrammarRegistry) async throws -> LanguageLayerTreeSnapshot

    private struct LocalParseWork: Sendable {
        let ticket: MarkdownParseAuthority.Ticket
        let window: MarkdownSectionCache.Window
        let content: String
        let delta: Int
        let expectedLength: Int
    }

    /// Optional measurement seam. Request time precedes queue admission, so
    /// request-to-resolution includes any queue wait and the physical parse.
    enum TimingEvent: Equatable {
        case storageEdit
        case parseRequested
        case parseResolved
        case published
    }

    var onTimingEvent: ((TimingEvent, UInt64) -> Void)?

    private let textSystem: EditorTextSystem
    private let registry: GrammarRegistry
    private let parseSnapshot: SnapshotParser
    private weak var boundStorage: NSTextStorage?
    private let authority = MarkdownParseAuthority()
    private let pairing = MarkdownEditPairing<MarkdownSectionCache.Window>()
    private var cache: MarkdownSectionCache?
    private var cacheMatchesStorage = false
    private let cacheRetirement = BoundedMarkdownCacheRetirement.shared
    private var parseTask: Task<Void, Never>?
    private var isActive = true
    var onPublication: (() -> Void)?
    private(set) var selectedWindowCount = 0
    private(set) var matchedWindowCount = 0
    private(set) var unpairedWindowCount = 0
    private(set) var historyEditAdmissionCount = 0
    private(set) var localParseCount = 0
    private(set) var fullParseCount = 0

    init(textSystem: EditorTextSystem, registry: GrammarRegistry,
         parseSnapshot: @escaping SnapshotParser = { source, registry in
             try await MarkdownViewportParseQueue.shared.snapshot(source: source, registry: registry)
         }) {
        self.textSystem = textSystem
        self.registry = registry
        self.parseSnapshot = parseSnapshot
        boundStorage = textSystem.textView.textStorage
    }

    func begin() {
        guard isActive else { return }
        authority.invalidatePresentation()
        guard let ticket = authority.ticket() else { return }
        parseTask?.cancel()
        retireCache()
        cacheMatchesStorage = false
        onPublication?()
        startFullParse(ticket: ticket)
    }

    /// `oldSource` belongs to mutable TextKit storage and is used only in this
    /// call. The pairing object retains only the selected bounded window's
    /// owned content so TextKit's widened paragraph range can be verified.
    func prepare(range: NSRange, replacement: String, oldSource: NSString) {
        guard isActive else { return }
        pairing.prepare(range: range, replacement: replacement, oldSource: oldSource,
                        verificationRange: { $0.old }, select: { source, edit, replacement in
                            guard cacheMatchesStorage, let cache,
                                  let visible = boundedViewport()
                            else { return nil }
                            let selected = cache.select(
                                source: source,
                                edit: edit,
                                replacement: replacement,
                                visible: visible
                            ) ?? cache.selectStructuralHeading(
                                source: source,
                                edit: edit,
                                replacement: replacement,
                                visible: visible
                            )
                            if selected != nil {
                                selectedWindowCount &+= 1
                            }
                            return selected
                        })
    }

    /// Called from `HighlightingStorageGate.didProcessCharacterEditWithGeometry`.
    /// Only pairing and a bounded new-window copy happen within the storage
    /// delegate; parsing and publication are deferred.
    func didEdit(range: NSRange, delta: Int, postSource: NSString) {
        guard isActive else { return }
        emitTiming(.storageEdit)
        authority.noteStorageEdit()
        parseTask?.cancel()
        parseTask = nil
        let wasCurrent = cacheMatchesStorage
        cacheMatchesStorage = false
        let hadPreEdit = pairing.hadPreEdit
        let match = pairing.complete(editedRange: range, delta: delta, postSource: postSource)
        if match != nil {
            matchedWindowCount &+= 1
        }
        let viewport = boundedViewport()
        let historyProbe = historyEditProbe(viewport: viewport, editedRange: range, postLength: postSource.length)
        let unpairedWindow: MarkdownSectionCache.Window? = if !hadPreEdit, wasCurrent,
                                                              let cache, let visible = viewport ?? historyProbe {
            cache.selectUnpairedPostEdit(postSource: postSource, editedRange: range,
                                         delta: delta, visible: visible)
        } else {
            nil
        }
        if unpairedWindow != nil {
            unpairedWindowCount &+= 1
            if historyProbe != nil {
                historyEditAdmissionCount &+= 1
            }
        }
        guard let ticket = authority.ticket() else { return }
        Task { @MainActor [weak self] in
            guard let self, authority.admits(ticket) else { return }
            onPublication?()
        }
        if let window = match?.candidate ?? unpairedWindow, cache != nil,
           window.new.location >= 0,
           window.new.location <= postSource.length,
           window.new.length <= postSource.length - window.new.location {
            let content = postSource.substring(with: window.new)
            startLocalParse(ticket: ticket, window: window, content: content,
                            delta: delta, expectedLength: postSource.length)
        } else {
            retireCache()
            // An actor task runs after the storage delegate has returned.
            parseTask = Task { @MainActor [weak self] in
                guard let self, authority.admits(ticket) else { return }
                startFullParse(ticket: ticket)
            }
        }
    }

    private func retireCache() {
        guard let cache else { return }
        self.cache = nil
        cacheRetirement.retire(cache)
    }

    func invalidatePresentation() {
        guard isActive else { return }
        authority.invalidatePresentation()
        parseTask?.cancel()
        parseTask = nil
        if !cacheMatchesStorage, let ticket = authority.ticket() {
            startFullParse(ticket: ticket)
        }
        onPublication?()
    }

    func tearDown() {
        guard isActive else { return }
        isActive = false
        authority.tearDown()
        pairing.discard()
        parseTask?.cancel()
        parseTask = nil
        retireCache()
        cacheMatchesStorage = false
        onPublication = nil
        onTimingEvent = nil
    }

    /// A nil or oversized viewport cannot authorize a cache query. The
    /// painter must treat an empty result as plain text for that range.
    func visibleTokens(in requested: NSRange? = nil) -> [Token] {
        guard isActive, cacheMatchesStorage, let cache,
              let storage = textSystem.textView.textStorage,
              storage === boundStorage,
              let visible = boundedViewport()
        else { return [] }
        let range: NSRange
        if let requested {
            guard requested.location != NSNotFound, requested.location >= 0,
                  requested.length > 0, requested.location <= storage.length,
                  requested.length <= storage.length - requested.location
            else { return [] }
            range = NSIntersectionRange(visible, requested)
            guard range.length > 0 else { return [] }
        } else {
            range = visible
        }
        return (try? cache.tokens(in: range)) ?? []
    }

    /// A deterministic test seam. The task may first schedule a replacement
    /// parse after an unsupported edit, so observe that second task too.
    func waitForPendingParse() async {
        for _ in 0 ..< 3 {
            let task = parseTask
            await task?.value
            if cacheMatchesStorage || task == nil {
                return
            }
            await Task.yield()
        }
    }

    var pendingParseForTesting: Task<Void, Never>? {
        parseTask
    }

    private func boundedViewport() -> NSRange? {
        guard let visible = textSystem.visibleUTF16Range,
              visible.length > 0,
              visible.length <= MarkdownSectionCache.windowLimit
        else { return nil }
        return visible
    }

    /// TextKit can temporarily remove layout authority during undo/redo.
    /// This probe only selects a verified local parse; visibleTokens still
    /// requires the real viewport before any paint.
    private func historyEditProbe(viewport: NSRange?, editedRange: NSRange, postLength: Int) -> NSRange? {
        guard viewport == nil,
              textSystem.undoManager.isUndoing || textSystem.undoManager.isRedoing,
              editedRange.location >= 0, editedRange.location < postLength
        else { return nil }
        return NSRange(location: editedRange.location, length: 1)
    }

    private func startFullParse(ticket: MarkdownParseAuthority.Ticket) {
        guard authority.admits(ticket) else { return }
        fullParseCount &+= 1
        let source = textSystem.textView.string
        let registry = registry
        let parseSnapshot = parseSnapshot
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        emitTiming(.parseRequested)
        // TextKit can occupy the main actor after this callback. Begin the
        // bounded parse independently; only the ticketed publication returns.
        parseTask = Task.detached(priority: .userInitiated) { [weak self] in
            let enteredAt = DispatchTime.now().uptimeNanoseconds
            let snapshot = try? await parseSnapshot(source, registry)
            let returnedAt = DispatchTime.now().uptimeNanoseconds
            if ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_DISPLAY_BENCH"] == "1" {
                print("VIEWPORT-SESSION-PHASE kind=full utf16=\((source as NSString).length) " +
                    "task_wait_ms=\(Double(enteredAt - requestedAt) / 1_000_000) " +
                    "snapshot_ms=\(Double(returnedAt - enteredAt) / 1_000_000)")
            }
            await self?.publishFullParse(ticket: ticket, source: source, snapshot: snapshot,
                                         resolvedAt: returnedAt)
        }
    }

    private func startLocalParse(ticket: MarkdownParseAuthority.Ticket,
                                 window: MarkdownSectionCache.Window, content: String,
                                 delta: Int, expectedLength: Int) {
        localParseCount &+= 1
        let work = LocalParseWork(ticket: ticket, window: window, content: content,
                                  delta: delta, expectedLength: expectedLength)
        let registry = registry
        let parseSnapshot = parseSnapshot
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        emitTiming(.parseRequested)
        // The next visible paint must not wait for a main-actor parse kickoff.
        parseTask = Task.detached(priority: .userInitiated) { [weak self] in
            let enteredAt = DispatchTime.now().uptimeNanoseconds
            let snapshot = try? await parseSnapshot(content, registry)
            let returnedAt = DispatchTime.now().uptimeNanoseconds
            if ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_DISPLAY_BENCH"] == "1" {
                print("VIEWPORT-SESSION-PHASE kind=local utf16=\((content as NSString).length) " +
                    "task_wait_ms=\(Double(enteredAt - requestedAt) / 1_000_000) " +
                    "snapshot_ms=\(Double(returnedAt - enteredAt) / 1_000_000)")
            }
            await self?.publishLocalParse(work: work, snapshot: snapshot, resolvedAt: returnedAt)
        }
    }

    private func emitTiming(_ event: TimingEvent) {
        onTimingEvent?(event, DispatchTime.now().uptimeNanoseconds)
    }
}

private extension MarkdownViewportSession {
    private func publishFullParse(ticket: MarkdownParseAuthority.Ticket, source: String,
                                  snapshot: LanguageLayerTreeSnapshot?, resolvedAt: UInt64) {
        emitPublicationWait(resolvedAt)
        emitTiming(.parseResolved)
        guard authority.admits(ticket), let snapshot,
              textSystem.textView.textStorage === boundStorage,
              textSystem.textView.textStorage?.length == (source as NSString).length
        else { return }
        cache = try? MarkdownSectionCache(source: source, snapshot: snapshot)
        cacheMatchesStorage = cache != nil
        emitTiming(.published)
        onPublication?()
    }

    private func publishLocalParse(work: LocalParseWork, snapshot: LanguageLayerTreeSnapshot?, resolvedAt: UInt64) {
        emitPublicationWait(resolvedAt)
        emitTiming(.parseResolved)
        guard authority.admits(work.ticket),
              textSystem.textView.textStorage === boundStorage,
              textSystem.textView.textStorage?.length == work.expectedLength
        else { return }
        guard let snapshot, var cache else {
            retireCache()
            startFullParse(ticket: work.ticket)
            return
        }
        do {
            try cache.replace(work.window, with: snapshot, content: work.content, delta: work.delta)
            self.cache = cache
            cacheMatchesStorage = true
            emitTiming(.published)
            onPublication?()
        } catch {
            retireCache()
            cacheMatchesStorage = false
            startFullParse(ticket: work.ticket)
        }
    }

    private func emitPublicationWait(_ resolvedAt: UInt64) {
        guard ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_DISPLAY_BENCH"] == "1" else { return }
        let enteredAt = DispatchTime.now().uptimeNanoseconds
        print("VIEWPORT-PUBLICATION-PHASE actor_wait_ms=\(Double(enteredAt - resolvedAt) / 1_000_000)")
    }
}
