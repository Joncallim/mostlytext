import Combine
import FileCore
import Foundation

/// Content-derived status metrics (#183 F16). Large-document computation runs
/// off the editor's actor and is published only for the current revision.
public struct EditorDocumentMetrics: Equatable, Sendable {
    public let characterCount: Int
    public let wordCount: Int
    public let lineEndings: LineEndingProfile

    public init(of text: String) {
        self.init(of: text, stopIf: { false })
    }

    init(of text: String, stopIf: @escaping () -> Bool) {
        characterCount = text.count
        wordCount = Self.wordCount(in: text, stopIf: stopIf)
        lineEndings = stopIf() ? LineEndingProfile() : LineEndingProfile(detecting: text)
    }

    /// Foundation's own word-boundary logic. `nonisolated` is required:
    /// `enumerateSubstrings` may invoke its block off the actor executor.
    public nonisolated static func wordCount(in text: String) -> Int {
        wordCount(in: text, stopIf: { false })
    }

    nonisolated static func wordCount(in text: String, stopIf: @escaping () -> Bool) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, stop in
            if (count & 0xFF) == 0, stopIf() {
                stop = true
                return
            }
            count += 1
        }
        return count
    }
}

/// Publishes metrics for a frozen text snapshot without blocking the editor.
/// A newer edit retires older work even when Foundation's word enumerator
/// cannot stop midway through its scan.
/// Foundation may invoke its enumeration block outside the Swift task's
/// executor. A locked token makes cancellation visible on that callback too.
final class EditorMetricsCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

@MainActor
public final class EditorDocumentMetricsStore: ObservableObject {
    @Published private var published: EditorDocumentMetrics?
    private var publishedRevision: UInt64?
    private var requestedRevision: UInt64?
    private var requestedLength = 0
    private var work: Task<Void, Never>?
    private var retiredWork: Task<Void, Never>?
    private var cancellation: EditorMetricsCancellation?
    private let compute: @Sendable (String, EditorMetricsCancellation) async -> EditorDocumentMetrics
    /// Completed scans accepted for the current revision (test-observable).
    private(set) var computationCount = 0

    public init() {
        compute = { text, cancellation in
            EditorDocumentMetrics(of: text, stopIf: cancellation.isCancelled)
        }
    }

    init(compute: @escaping @Sendable (String, EditorMetricsCancellation) async -> EditorDocumentMetrics) {
        self.compute = compute
    }

    deinit {
        cancellation?.cancel()
        work?.cancel()
        retiredWork?.cancel()
    }

    public func metrics(for revision: UInt64) -> EditorDocumentMetrics? {
        publishedRevision == revision ? published : nil
    }

    public func request(revision: UInt64, length: Int, text: () -> String) {
        guard requestedRevision != revision || requestedLength != length else { return }
        requestedRevision = revision
        requestedLength = length
        retiredWork = work
        cancellation?.cancel()
        work?.cancel()
        let compute = compute
        let frozen = text()
        let cancellation = EditorMetricsCancellation()
        self.cancellation = cancellation
        work = Task.detached(priority: .utility) { [weak self] in
            let result = await compute(frozen, cancellation)
            guard !cancellation.isCancelled(), !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, requestedRevision == revision,
                      requestedLength == length else { return }
                publishedRevision = revision
                computationCount += 1
                published = result
            }
        }
    }

    func settle() async {
        await work?.value
    }

    func settleRetired() async {
        await retiredWork?.value
    }
}

public extension EditorTextSystem {
    var documentMetricsStore: EditorDocumentMetricsStore {
        metricsStore
    }

    /// Copies a stable text value on the main actor, then runs the three
    /// content-derived scans off-main. Selection changes do not schedule work.
    func requestDocumentMetrics() {
        metricsStore.request(revision: editRevision, length: liveUTF16Length) { text }
    }

    /// The live text as an `NSString` without a whole-document `String` copy.
    var liveTextSource: NSString {
        assistTextSource ?? (text as NSString)
    }

    private var liveUTF16Length: Int {
        assistTextSource?.length ?? (text as NSString).length
    }
}
