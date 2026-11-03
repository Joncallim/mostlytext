import Foundation
import Observation

/// The result of analyzing one immutable JSON text snapshot: the single
/// diagnostic when the document is invalid, or the outline items when it is
/// valid (EPIC-11 §3.3/§3.4).
public struct JSONAnalysisResult: Sendable, Equatable {
    /// The snapshot that produced this result.
    public let text: String
    /// The parser's single diagnostic, or `nil` for a valid document.
    public let diagnostic: JSONDiagnostic?
    /// The outline tree for a valid document; empty for an invalid one.
    public let outlineItems: [ContentOutlineItem]

    public init(text: String, diagnostic: JSONDiagnostic?, outlineItems: [ContentOutlineItem]) {
        self.text = text
        self.diagnostic = diagnostic
        self.outlineItems = outlineItems
    }

    /// `true` when the snapshot is a valid JSON document.
    public var isValid: Bool {
        diagnostic == nil
    }
}

/// Pure JSON analysis — parse plus outline — for one immutable text snapshot.
///
/// Nonisolated so callers can run it off the main actor; the session wraps it
/// in a detached task.
public enum JSONAnalyzer {
    public static func analyze(_ text: String) -> JSONAnalysisResult {
        switch JSONOutlineBuilder.outline(text) {
        case let .valid(items):
            JSONAnalysisResult(text: text, diagnostic: nil, outlineItems: items)
        case let .invalid(diagnostic):
            JSONAnalysisResult(text: text, diagnostic: diagnostic, outlineItems: [])
        }
    }
}

/// Per-document debounce + publish for JSON analysis (EPIC-11 §3.3/§3.4).
///
/// Mirrors `MarkdownParseSession`: one session per open document, owned via
/// ``JSONAnalysisStore``. Rapid valid→invalid→valid edits publish only the
/// latest result, and analysis runs off the main actor.
@MainActor
@Observable
public final class JSONAnalysisSession {
    /// The latest completed analysis, or `nil` before the first completion.
    public private(set) var result: JSONAnalysisResult?

    /// True while an analysis task is pending or running.
    public private(set) var isAnalyzing = false

    /// Completed-analysis counter — exists for the debounce acceptance test.
    public private(set) var completedAnalysisCount = 0

    private let debounce: Duration
    private let analyze: @Sendable (String) -> JSONAnalysisResult
    private var pendingTask: Task<Void, Never>?
    private var pendingGeneration = 0
    private var lastText = ""
    private var immediateAnalysisCount = 0

    /// `debounce` is injectable so tests run fast; production uses the default.
    public init(debounce: Duration = .milliseconds(150)) {
        self.debounce = debounce
        analyze = JSONAnalyzer.analyze
    }

    /// Test seam: substitutes the analyzer so a test can hold an analysis in
    /// flight and release it after the request has been superseded.
    init(debounce: Duration, analyze: @escaping @Sendable (String) -> JSONAnalysisResult) {
        self.debounce = debounce
        self.analyze = analyze
    }

    /// Debounced: cancels any pending analysis and schedules a new one after
    /// `debounce`. Coalesces rapid keystrokes into ≤ 2 analyses.
    public func textDidChange(_ text: String) {
        lastText = text
        isAnalyzing = true
        pendingTask?.cancel()

        // Capture the post-increment value: clearIfCurrent only resets state
        // when no newer schedule has superseded this one, so the stored
        // counter and the captured generation must match for the latest
        // schedule.
        pendingGeneration += 1
        let generation = pendingGeneration

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
            await analyzeAndPublish(text: text, generation: generation)
            clearIfCurrent(generation: generation)
        }
    }

    /// Immediate analysis, bypassing the debounce (document open, tests).
    /// Cancels any pending debounced analysis first. Publishes AND returns.
    ///
    /// If the calling task is cancelled, or this request is superseded (a
    /// newer edit, another immediate analysis, or `cancelPending()`) before
    /// the analysis completes, the result is still returned but never
    /// published. An already-cancelled caller's result is computed off the
    /// main actor and returned without touching any state.
    @discardableResult
    public func analyzeNow(_ text: String) async -> JSONAnalysisResult {
        guard !Task.isCancelled else {
            let analyze = analyze
            return await Task.detached(priority: .utility) { analyze(text) }.value
        }
        immediateAnalysisCount += 1
        defer {
            immediateAnalysisCount -= 1
            refreshAnalyzingState()
        }
        lastText = text
        pendingGeneration += 1
        let generation = pendingGeneration
        pendingTask?.cancel()

        let result = await analyzeAndPublish(text: text, generation: generation)
        clearIfCurrent(generation: generation)
        return result
    }

    /// Cancels any pending/running analysis without publishing.
    public func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingGeneration += 1
        refreshAnalyzingState()
    }

    // MARK: - Analysis

    /// Runs the analysis off the main actor and publishes the result.
    @discardableResult
    private func analyzeAndPublish(text: String, generation: Int) async -> JSONAnalysisResult {
        isAnalyzing = true
        defer { refreshAnalyzingState() }

        let analyze = analyze
        let outcome = await Task.detached(priority: .utility) {
            analyze(text)
        }.value
        // Publish only for the request that is still current. Cancelling the
        // task is not enough: `cancelPending()` and newer requests invalidate
        // a request by generation, and an analyzeNow caller's own task is not
        // the stored pending task (#183 F04).
        guard !Task.isCancelled, pendingGeneration == generation else { return outcome }
        result = outcome
        completedAnalysisCount += 1
        return outcome
    }

    private func clearIfCurrent(generation: Int) {
        guard pendingGeneration == generation else { return }
        pendingTask = nil
        refreshAnalyzingState()
    }

    /// Actual immediate workers remain busy until they return, even when their
    /// publication was cancelled or a newer generation already completed.
    private func refreshAnalyzingState() {
        isAnalyzing = pendingTask != nil || immediateAnalysisCount > 0
    }
}

/// identity (tab UUID string) → session. Mirrors `MarkdownParseStore`.
@MainActor
public final class JSONAnalysisStore {
    private let debounce: Duration
    private var sessions: [String: JSONAnalysisSession] = [:]

    public init(debounce: Duration = .milliseconds(150)) {
        self.debounce = debounce
    }

    public func session(for identity: String) -> JSONAnalysisSession {
        if let session = sessions[identity] {
            return session
        }
        let session = JSONAnalysisSession(debounce: debounce)
        sessions[identity] = session
        return session
    }

    public func existingSession(for identity: String) -> JSONAnalysisSession? {
        sessions[identity]
    }

    public func evict(_ identity: String) {
        sessions.removeValue(forKey: identity)
    }

    public func evictAll() {
        sessions.removeAll()
    }
}
