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

    private let textSystem: EditorTextSystem
    private let registry: GrammarRegistry
    private let parseSnapshot: SnapshotParser
    private weak var boundStorage: NSTextStorage?
    private let authority = MarkdownParseAuthority()
    private let pairing = MarkdownEditPairing<MarkdownSectionCache.Window>()
    private var cache: MarkdownSectionCache?
    private var cacheMatchesStorage = false
    private var parseTask: Task<Void, Never>?
    private var isActive = true
    var onPublication: (() -> Void)?

    init(textSystem: EditorTextSystem, registry: GrammarRegistry,
         parseSnapshot: @escaping SnapshotParser = { source, registry in
             try await Task.detached(priority: .utility) {
                 try MarkdownSectionParser.snapshot(source: source, registry: registry)
             }.value
         }) {
        self.textSystem = textSystem
        self.registry = registry
        self.parseSnapshot = parseSnapshot
        boundStorage = textSystem.textView.textStorage
    }

    func begin() {
        guard isActive, let ticket = authority.ticket() else { return }
        parseTask?.cancel()
        cache = nil
        cacheMatchesStorage = false
        startFullParse(ticket: ticket)
    }

    /// `oldSource` belongs to mutable TextKit storage and is used only in this
    /// call. The pairing object retains geometry and a cache window, not text.
    func prepare(range: NSRange, replacement: String, oldSource: NSString) {
        guard isActive else { return }
        pairing.prepare(range: range, replacement: replacement, oldSource: oldSource) { source, edit, replacement in
            guard cacheMatchesStorage, let cache,
                  let visible = boundedViewport()
            else { return nil }
            return cache.select(source: source, edit: edit, replacement: replacement, visible: visible)
        }
    }

    /// Called from `HighlightingStorageGate.didProcessCharacterEditWithGeometry`.
    /// Only pairing and a bounded new-window copy happen within the storage
    /// delegate; parsing and publication are deferred.
    func didEdit(range: NSRange, delta: Int, postSource: NSString) {
        guard isActive else { return }
        authority.noteStorageEdit()
        parseTask?.cancel()
        parseTask = nil
        cacheMatchesStorage = false
        let match = pairing.complete(editedRange: range, delta: delta, postSource: postSource)
        guard let ticket = authority.ticket() else { return }
        Task { @MainActor [weak self] in
            guard let self, authority.admits(ticket) else { return }
            onPublication?()
        }
        if let match, cache != nil,
           match.candidate.new.location >= 0,
           match.candidate.new.location <= postSource.length,
           match.candidate.new.length <= postSource.length - match.candidate.new.location {
            let content = postSource.substring(with: match.candidate.new)
            startLocalParse(ticket: ticket, window: match.candidate, content: content,
                            delta: delta, expectedLength: postSource.length)
        } else {
            cache = nil
            // An actor task runs after the storage delegate has returned.
            parseTask = Task { @MainActor [weak self] in
                guard let self, authority.admits(ticket) else { return }
                startFullParse(ticket: ticket)
            }
        }
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
        cache = nil
        cacheMatchesStorage = false
        onPublication = nil
    }

    /// A nil or oversized viewport cannot authorize a cache query. The
    /// painter must treat an empty result as plain text for that range.
    func visibleTokens() -> [Token] {
        guard isActive, cacheMatchesStorage, let cache,
              textSystem.textView.textStorage === boundStorage,
              let visible = boundedViewport()
        else { return [] }
        return (try? cache.tokens(in: visible)) ?? []
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

    private func startFullParse(ticket: MarkdownParseAuthority.Ticket) {
        guard authority.admits(ticket) else { return }
        let source = textSystem.textView.string
        let registry = registry
        let parseSnapshot = parseSnapshot
        parseTask = Task { [weak self] in
            let snapshot = try? await parseSnapshot(source, registry)
            guard let self, authority.admits(ticket), let snapshot,
                  textSystem.textView.textStorage === boundStorage,
                  textSystem.textView.textStorage?.length == (source as NSString).length
            else { return }
            cache = try? MarkdownSectionCache(source: source, snapshot: snapshot)
            cacheMatchesStorage = cache != nil
            onPublication?()
        }
    }

    private func startLocalParse(ticket: MarkdownParseAuthority.Ticket,
                                 window: MarkdownSectionCache.Window, content: String,
                                 delta: Int, expectedLength: Int) {
        let registry = registry
        let parseSnapshot = parseSnapshot
        parseTask = Task { [weak self] in
            let snapshot = try? await parseSnapshot(content, registry)
            guard let self, authority.admits(ticket),
                  textSystem.textView.textStorage === boundStorage,
                  textSystem.textView.textStorage?.length == expectedLength
            else { return }
            guard let snapshot, var cache else {
                cache = nil
                startFullParse(ticket: ticket)
                return
            }
            do {
                try cache.replace(window, with: snapshot, content: content, delta: delta)
                self.cache = cache
                cacheMatchesStorage = true
                onPublication?()
            } catch {
                self.cache = nil
                cacheMatchesStorage = false
                startFullParse(ticket: ticket)
            }
        }
    }
}
