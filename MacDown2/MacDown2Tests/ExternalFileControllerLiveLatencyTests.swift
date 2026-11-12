import CryptoKit
import Darwin
import EditorCore
@testable import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// Measures rename-start to completed controller reconciliation on a real
/// directory watcher. The observed times are evidence, not a release ceiling.
@Suite("External file controller live latency", .serialized)
@MainActor
struct ExternalFileControllerLiveLatencyTests {
    @Test(arguments: [1_000_000, 10_000_000])
    func aRealWatcherReconcilesTheEditorAndModel(byteCount: Int) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("mostlytext-controller-latency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.md")
        let replacementURL = directory.appendingPathComponent("replacement.md")
        let original = String(repeating: "A", count: byteCount)
        let replacement = String(repeating: "B", count: byteCount)
        try Data(original.utf8).write(to: sourceURL)
        try Data(replacement.utf8).write(to: replacementURL)
        let digest = SHA256.hash(data: Data(replacement.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).load()
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: recovery
        )
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        let editorStore = EditorTextSystemStore()
        let identity = "external-latency-\(UUID().uuidString)"
        let editor = editorStore.system(for: identity, initialText: original, configuration: .default)
        let phases = WatcherPhaseRecorder()
        let monitor = makeMonitor(phases: phases)
        let controller = ExternalFileController(model: model, editorStore: editorStore,
                                                identity: identity, monitor: monitor)
        defer { controller.dispose() }
        let recorder = ReconciliationRecorder()
        controller.afterObservationContextHandled = { context in
            guard case let .available(snapshot) = context.observation,
                  model.activeDocument?.lastKnownRevision?.sha256 == snapshot.revision.sha256
            else { return }
            recorder.append(context)
        }
        controller.synchronize(with: document)
        await controller.bindTask?.value
        try await waitUntil("initial watcher observation") { !recorder.records.isEmpty }

        let began = phases.begin()
        guard rename(replacementURL.path, sourceURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try await waitUntil("controller reconciliation") { recorder.timestamp(for: digest) != nil }
        let reconciled = try #require(recorder.timestamp(for: digest))
        try verifyReconciled(model: model, editorText: editor.textView.string,
                             replacement: replacement, sourceURL: sourceURL)
        let trace = try #require(phases.trace(before: reconciled))
        #expect(trace.firstEvent >= began && trace.debounceStart >= trace.lastEvent)
        try record(byteCount: byteCount, digest: digest, began: began,
                   reconciled: reconciled, trace: trace)
    }

    private func makeMonitor(phases: WatcherPhaseRecorder) -> DocumentFileMonitor {
        DocumentFileMonitor(debounce: .milliseconds(150), watcher: TimedLiveWatcher(phases: phases),
                            prober: DocumentFileProbe(), sleeper: { duration in
                                let start = DispatchTime.now().uptimeNanoseconds
                                do {
                                    try await Task.sleep(for: duration)
                                    phases.completedDebounce(duration: duration, start: start,
                                                             end: DispatchTime.now().uptimeNanoseconds)
                                } catch {
                                    // Cancellation of a superseded debounce is product behavior.
                                }
                            })
    }

    private func verifyReconciled(model: WorkspaceModel, editorText: String, replacement: String,
                                  sourceURL: URL) throws {
        #expect(model.activeDocument?.state == .clean)
        #expect(model.activeDocument?.text == replacement)
        #expect(editorText == replacement)
        #expect(try Data(contentsOf: sourceURL) == Data(replacement.utf8))
    }

    private func record(byteCount: Int, digest: String, began: UInt64, reconciled: UInt64,
                        trace: WatcherPhaseRecorder.Trace) throws {
        print("controller-latency bytes=\(byteCount) " +
            "rename_to_first_event_ms=\(ms(began, trace.firstEvent)) " +
            "last_event_to_debounce_start_ms=\(ms(trace.lastEvent, trace.debounceStart)) " +
            "actual_debounce_ms=\(ms(trace.debounceStart, trace.debounceEnd)) " +
            "debounce_end_to_model_and_editor_ms=\(ms(trace.debounceEnd, reconciled)) " +
            "rename_start_to_model_and_editor_ms=\(ms(began, reconciled))")
        if let path = ProcessInfo.processInfo.environment["MOSTLYTEXT_CONTROLLER_LATENCY_OUTPUT"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let values: [String: Any] = [
                "bytes": byteCount,
                "revision_sha256": digest,
                "rename_to_first_event_ms": ms(began, trace.firstEvent),
                "last_event_to_debounce_start_ms": ms(trace.lastEvent, trace.debounceStart),
                "actual_debounce_ms": ms(trace.debounceStart, trace.debounceEnd),
                "debounce_end_to_model_and_editor_ms": ms(trace.debounceEnd, reconciled),
                "rename_start_to_model_and_editor_ms": ms(began, reconciled),
            ]
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("\(byteCount).json"), options: .atomic)
        }
    }

    private func ms(_ start: UInt64, _ end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    private func waitUntil(_ stage: String, condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(stage)")
        throw CancellationError()
    }
}

@MainActor
private final class ReconciliationRecorder {
    private(set) var records: [(digest: String, timestamp: UInt64)] = []

    func append(_ context: DocumentFileObservationContext) {
        guard case let .available(snapshot) = context.observation else { return }
        records.append((snapshot.revision.sha256, DispatchTime.now().uptimeNanoseconds))
    }

    func timestamp(for digest: String) -> UInt64? {
        records.first { $0.digest == digest }?.timestamp
    }
}

private struct TimedLiveWatcher: DocumentDirectoryWatching {
    let phases: WatcherPhaseRecorder
    private let live = LiveDocumentDirectoryWatcher()

    func watch(
        _ directoryURL: URL, onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle {
        try live.watch(directoryURL) { signal in
            phases.noteSignal()
            onSignal(signal)
        }
    }

    func watchFile(
        _ fileURL: URL, onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle {
        try live.watchFile(fileURL) { signal in
            phases.noteSignal()
            onSignal(signal)
        }
    }
}

private final class WatcherPhaseRecorder: @unchecked Sendable {
    struct Trace {
        let firstEvent: UInt64
        let lastEvent: UInt64
        let debounceStart: UInt64
        let debounceEnd: UInt64
    }

    private let lock = NSLock()
    private var begun: UInt64?
    private var events: [UInt64] = []
    private var debounces: [(start: UInt64, end: UInt64)] = []

    func begin() -> UInt64 {
        lock.withLock {
            let now = DispatchTime.now().uptimeNanoseconds
            begun = now
            events.removeAll()
            debounces.removeAll()
            return now
        }
    }

    func noteSignal() {
        lock.withLock {
            if begun != nil {
                events.append(DispatchTime.now().uptimeNanoseconds)
            }
        }
    }

    func completedDebounce(duration: Duration, start: UInt64, end: UInt64) {
        guard duration == .milliseconds(150) else { return }
        lock.withLock {
            if begun != nil {
                debounces.append((start, end))
            }
        }
    }

    func trace(before reconciled: UInt64) -> Trace? {
        lock.withLock {
            guard let debounce = debounces.last(where: { $0.end <= reconciled }),
                  let first = events.first,
                  let last = events.last(where: { $0 <= debounce.start })
            else { return nil }
            return Trace(firstEvent: first, lastEvent: last,
                         debounceStart: debounce.start, debounceEnd: debounce.end)
        }
    }
}
