import Foundation
import Observation
import os.log

/// Per-document debounce + publish. One per open document, owned via the store.
@MainActor
@Observable
public final class MarkdownParseSession {
    /// Stable for this session's lifetime and never reused. `ObjectIdentifier(session)` is NOT: a freed session's
    /// address is handed to the next one, so two tabs could share an "identity" and a tab switch looked like
    /// the same document.
    public let identity = UUID()

    /// Latest completed parse. nil until the first parse completes.
    public private(set) var document: MarkdownDocument?

    /// The source text that produced `document`. Published in the same mutation
    /// so preview consumers can snapshot the text that corresponds to the AST.
    public private(set) var publishedText: String?

    /// True while a parse Task is pending or running (drives subtle UI later).
    public private(set) var isParsing: Bool = false

    /// Completed-parse counter — exists for the debounce acceptance test.
    public private(set) var completedParseCount: Int = 0

    private let engine: any ParseExecuting
    private var options: MarkdownParseOptions
    private let debounce: Duration
    private var pendingTask: Task<Void, Never>?
    private var pendingGeneration: Int = 0
    private var nextRevision: Int = 1
    private var lastText: String = ""
    private var immediateParseCount = 0

    /// `debounce` is injectable so tests run fast; production uses the default.
    public init(
        engine: any ParseExecuting = ParseEngine(),
        options: MarkdownParseOptions = .default,
        debounce: Duration = .milliseconds(150)
    ) {
        self.engine = engine
        self.options = options
        self.debounce = debounce
    }

    /// Debounced: cancels any pending parse and schedules a new one after
    /// `debounce`. Coalesces rapid keystrokes into ≤ 2 parses (acceptance).
    public func textDidChange(_ text: String) {
        lastText = text
        isParsing = true
        pendingTask?.cancel()

        // Capture the post-increment value: clearIfCurrent only resets state
        // when no newer schedule has superseded this one, so the stored counter
        // and the captured generation must match for the latest schedule.
        pendingGeneration += 1
        let generation = pendingGeneration

        let revision = nextRevision
        nextRevision += 1

        pendingTask = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
            } catch is CancellationError {
                clearIfCurrent(generation: generation)
                return
            } catch {
                clearIfCurrent(generation: generation)
                return
            }
            await parse(text: text, revision: revision, generation: generation)
            clearIfCurrent(generation: generation)
        }
    }

    /// Immediate parse, bypassing the debounce (document open, tests).
    /// Cancels any pending debounced parse first. Publishes AND returns.
    ///
    /// If the caller is cancelled or a newer request/cancelPending supersedes
    /// this generation before completion, the result is discarded without publication. This prevents a stale parse for
    /// a tab that SwiftUI has already switched away from from overwriting the
    /// session.
    @discardableResult
    public func parseNow(_ text: String) async -> MarkdownDocument? {
        guard !Task.isCancelled else { return nil }
        lastText = text
        pendingGeneration += 1
        let generation = pendingGeneration
        pendingTask?.cancel()

        immediateParseCount += 1
        defer {
            immediateParseCount -= 1
            refreshParsingState()
        }

        // clearIfCurrent runs before this defer; no suspension point may be
        // inserted between them or the deferred count decrement would race.
        let revision = nextRevision
        nextRevision += 1
        let result = await parse(text: text, revision: revision, generation: generation)
        clearIfCurrent(generation: generation)
        return result
    }

    /// Cancels any pending/running parse without publishing.
    public func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingGeneration += 1
        refreshParsingState()
    }

    /// Reparse the last text with new options (E13 will call this; tests now).
    public func setOptions(_ options: MarkdownParseOptions) {
        self.options = options
        textDidChange(lastText)
    }

    @discardableResult
    private func parse(text: String, revision: Int, generation: Int) async -> MarkdownDocument? {
        isParsing = true
        defer { refreshParsingState() }

        do {
            let result = try await engine.parse(text, options: options, revision: revision)
            // Session cancellation and newer requests also revoke publication, even when the immediate
            // caller itself remains alive. Physical work stays counted until its own await returns.
            guard !Task.isCancelled, pendingGeneration == generation else { return nil }
            guard result.revision > (document?.revision ?? 0) else {
                return nil
            }
            document = result
            publishedText = text
            completedParseCount += 1
            return result
        } catch is CancellationError {
            return nil
        } catch {
            os_log("Markdown parse failed: %{public}@", error.localizedDescription)
            return nil
        }
    }

    private func clearIfCurrent(generation: Int) {
        guard pendingGeneration == generation else { return }
        pendingTask = nil
        refreshParsingState()
    }

    /// The session is busy exactly while a debounced parse is scheduled or
    /// any immediate parse has not yet returned. Deriving it from that
    /// outstanding work (rather than from whichever parse completed last)
    /// keeps an older completion from reporting idle under a newer parse.
    private func refreshParsingState() {
        isParsing = pendingTask != nil || immediateParseCount > 0
    }
}
