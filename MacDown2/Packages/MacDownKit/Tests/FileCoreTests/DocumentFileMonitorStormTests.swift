@testable import FileCore
import Foundation
import Testing

private actor HeldStormProber: DocumentFileProbing {
    private let initial: FileSnapshot
    private let disk: FileSnapshot
    private var held: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var calls = 0

    init(initial: FileSnapshot, disk: FileSnapshot) {
        self.initial = initial
        self.disk = disk
    }

    func observe(
        expectedURL _: URL,
        priorFileObjectID _: PhysicalFileIdentity.FileObjectID?,
        decoding _: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        calls += 1
        if calls == 1 {
            return .available(initial)
        }
        if !released {
            await withCheckedContinuation { held.append($0) }
        }
        return .available(disk)
    }

    func release() {
        released = true
        let pending = held
        held.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor HeldRebindProber: DocumentFileProbing {
    let first: FileSnapshot
    let stale: FileSnapshot
    let second: FileSnapshot
    let updated: FileSnapshot
    private var held: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    init(first: FileSnapshot, stale: FileSnapshot, second: FileSnapshot, updated: FileSnapshot) {
        self.first = first
        self.stale = stale
        self.second = second
        self.updated = updated
    }

    func observe(
        expectedURL _: URL,
        priorFileObjectID _: PhysicalFileIdentity.FileObjectID?,
        decoding _: FileDecodingPolicy
    ) async -> DocumentFileObservation {
        calls += 1
        switch calls {
        case 1: return .available(first)
        case 2:
            await withCheckedContinuation { held = $0 }
            return .available(stale)
        case 3: return .available(second)
        default: return .available(updated)
        }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

@Suite("Document file monitor storm admission")
struct DocumentFileMonitorStormTests {
    @Test func realAtomicWriteStormKeepsProbeFanoutBounded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("storm.md")
        try Data("initial".utf8).write(to: url, options: .atomic)

        let initial = snapshot("initial", at: url)
        let final = snapshot("last external version", at: url)
        let prober = HeldStormProber(initial: initial, disk: final)
        let recorder = ObservationRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .milliseconds(10),
            watcher: LiveDocumentDirectoryWatcher(),
            prober: prober,
            sleeper: { duration in try? await Task.sleep(for: duration) }
        )
        try await monitor.bind(to: url, priorFileObjectID: nil) { recorder.append($0) }
        #expect(recorder.values == [.available(initial)])

        // Force one real kqueue-triggered probe to remain in flight while
        // independent atomic replacements continue changing the file.
        try Data("first replacement".utf8).write(to: url, options: .atomic)
        await waitUntil({ await prober.calls == 2 }, timeout: .seconds(5))
        for index in 0 ..< 40 {
            try Data("external version \(index)".utf8).write(to: url, options: .atomic)
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(await prober.calls == 2, "real write events must not spawn overlapping disk probes")
        #expect(try String(contentsOf: url, encoding: .utf8) == "external version 39")

        await prober.release()
        await waitUntil({ recorder.count >= 2 }, timeout: .seconds(5))
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.values.last == .available(final))
        let finalProbeCalls = await prober.calls
        #expect(finalProbeCalls >= 3, "the later real writes require a fresh probe")
        #expect(finalProbeCalls <= 8, "forty real writes must not fan out to unbounded disk probes")
        await monitor.cancel()
    }

    @Test func slowProbeAllowsOnlyOneLatestFollowupAfterManyDebouncedSignals() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic18/storm.md")
        let initial = snapshot("initial", at: url)
        let disk = snapshot("final disk contents", at: url)
        let prober = HeldStormProber(initial: initial, disk: disk)
        let sleeper = GateSleeper()
        let recorder = ObservationRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: MonitorWatcher(),
            prober: prober,
            sleeper: { _ in await sleeper.sleep() }
        )
        try await monitor.bind(to: url, priorFileObjectID: nil) { recorder.append($0) }
        let generation = await monitor.generation

        // Every signal gets past its debounce while the first disk probe is
        // deliberately suspended. This exposes overlap that a burst entirely
        // within the debounce interval cannot exercise.
        for signal in 0 ..< 8 {
            await monitor.received(.changed, generation: generation)
            await waitUntil { await sleeper.waiterCount == 1 }
            await sleeper.resumeAll()
            if signal == 0 {
                await waitUntil { await prober.calls == 2 }
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        let callsBeforeRelease = await prober.calls
        #expect(
            callsBeforeRelease == 2,
            "a held disk probe must not spawn another probe per signal: \(callsBeforeRelease)"
        )

        await prober.release()
        await waitUntil { recorder.count == 2 }
        #expect(recorder.values == [.available(initial), .available(disk)])
        #expect(await prober.calls == 3, "the latest signal must still receive one fresh disk probe")
        await monitor.cancel()
    }

    @Test func rebindCanProbeTheNewFileWhileTheOldFileProbeIsHeld() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/epic18/storm-first.md")
        let secondURL = URL(fileURLWithPath: "/tmp/epic18/storm-second.md")
        let first = snapshot("first", at: firstURL)
        let stale = snapshot("stale", at: firstURL)
        let second = snapshot("second", at: secondURL)
        let updated = snapshot("updated", at: secondURL)
        let prober = HeldRebindProber(first: first, stale: stale, second: second, updated: updated)
        let recorder = ObservationRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: MonitorWatcher(),
            prober: prober,
            sleeper: { _ in }
        )
        try await monitor.bind(to: firstURL, priorFileObjectID: nil) { recorder.append($0) }
        let firstGeneration = await monitor.generation
        await monitor.received(.changed, generation: firstGeneration)
        await waitUntil { await prober.calls == 2 }

        try await monitor.bind(to: secondURL, priorFileObjectID: nil) { recorder.append($0) }
        let secondGeneration = await monitor.generation
        await monitor.received(.changed, generation: secondGeneration)
        await waitUntil { recorder.count == 3 }
        #expect(recorder.values == [.available(first), .available(second), .available(updated)])

        await prober.release()
        await waitUntil { await monitor.probesInFlight.isEmpty }
        #expect(recorder.values == [.available(first), .available(second), .available(updated)])
        await monitor.cancel()
    }
}
