@testable import FileCore
import Foundation
import Testing

@Suite("Document file monitor")
struct DocumentFileMonitorTests {
    @Test func bindWatchesTheParentAndPerformsAnInitialProbe() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/notes.md")
        let watcher = MonitorWatcher()
        let prober = ScriptedProber([.available(snapshot("initial", at: fileURL))])
        let recorder = ObservationRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)

        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }

        await waitUntil { recorder.count == 1 }
        #expect(watcher.watchedDirectories == [fileURL.deletingLastPathComponent().standardizedFileURL])
        #expect(recorder.values == [.available(snapshot("initial", at: fileURL))])
    }

    @Test func rapidSignalsCoalesceToOneLatestProbe() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/coalesce.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let final = snapshot("final", at: fileURL)
        let prober = ScriptedProber([.available(initial), .available(final)])
        let recorder = ObservationRecorder()
        let sleeper = GateSleeper()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await sleeper.sleep() }
        )
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.changed)
        await waitUntil { await sleeper.waiterCount == 1 }
        watcher.signal(.changed)
        await waitUntil { await sleeper.waiterCount == 2 }
        await sleeper.resumeAll()

        await waitUntil { recorder.count == 2 }
        #expect(recorder.values == [.available(initial), .available(final)])
        #expect(await prober.callCount == 2)
    }

    @Test func fileLevelWatcherReportsAnInPlaceChildWrite() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/in-place.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let changed = snapshot("changed", at: fileURL)
        let prober = ScriptedProber([.available(initial), .available(changed)])
        let recorder = ObservationRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)

        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }
        watcher.signalFile(.changed)
        await waitUntil { recorder.count == 2 }

        #expect(recorder.values == [.available(initial), .available(changed)])
    }

    @Test func transientMissingIsConfirmedBeforeItIsEmitted() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/replace.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let replacement = snapshot("replacement", at: fileURL)
        let prober = ScriptedProber([
            .available(initial),
            .missing(fileURL),
            .available(replacement),
            .available(replacement),
        ])
        let recorder = ObservationRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.parentVanished)

        await waitUntil { recorder.count == 3 }
        #expect(recorder.values == [.available(initial), .available(replacement), .available(replacement)])
        #expect(await prober.callCount == 4)
    }

    @Test func rebindAndCancelRejectLateCallbacksFromEarlierGenerations() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/epic18/first.md")
        let secondURL = URL(fileURLWithPath: "/tmp/epic18/second.md")
        let watcher = MonitorWatcher()
        let first = snapshot("first", at: firstURL)
        let second = snapshot("second", at: secondURL)
        let stale = snapshot("stale", at: firstURL)
        let prober = ScriptedProber([.available(first), .available(second), .available(stale)])
        let recorder = ObservationRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)

        try await monitor.bind(to: firstURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }
        try await monitor.bind(to: secondURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 2 }

        watcher.signal(.changed, at: 0) // The cancelled first watcher fires late.
        await Task.yield()
        await Task.yield()
        #expect(recorder.values == [.available(first), .available(second)])
        #expect(await prober.callCount == 2)

        await monitor.cancel()
        watcher.signal(.changed, at: 1)
        await Task.yield()
        await Task.yield()
        #expect(recorder.values == [.available(first), .available(second)])
        #expect(watcher.cancelCount == 2)
    }

    @Test func newerSignalRejectsAnOlderInFlightProbe() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/probe-sequence.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let stale = snapshot("stale", at: fileURL)
        let latest = snapshot("latest", at: fileURL)
        let prober = DeferredProber(initial: initial)
        let recorder = ObservationRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.changed)
        await waitUntil { await prober.waiterCount == 1 }
        watcher.signal(.changed)
        await waitUntil { await monitor.currentRequestGeneration() == 3 }

        await prober.resume(stale, at: 0)
        await waitUntil { await prober.waiterCount == 2 }
        #expect(recorder.values == [.available(initial)])

        await prober.resume(latest, at: 1)
        await waitUntil { recorder.count == 2 }
        #expect(recorder.values == [.available(initial), .available(latest)])
    }

    @Test func observationContextRejectsAStaleMovedOrMissingProbeAfterANewSignal() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/context.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: fileURL)
        let stale = snapshot("stale", at: fileURL)
        let prober = DeferredProber(initial: initial)
        let contexts = ContextRecorder()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )
        try await monitor.bind(
            to: fileURL,
            priorFileObjectID: nil,
            onObservation: { _ in },
            onHealthChange: { _ in },
            onContext: { context in
                contexts.append(context)
            }
        )
        await waitUntil { contexts.count == 1 }
        watcher.signal(.changed)
        await waitUntil { await prober.waiterCount == 1 }
        watcher.signal(.changed)
        await waitUntil { await monitor.currentRequestGeneration() == 3 }

        await prober.resume(.moved(stale), at: 0)
        await waitUntil { await prober.waiterCount == 2 }
        #expect(contexts.count == 1)
        await prober.resume(.missing(fileURL), at: 1)
        await waitUntil { await prober.waiterCount == 3 }
        await prober.resume(.missing(fileURL), at: 2)
        await waitUntil { contexts.count == 2 }
        #expect(contexts.values.last?.observation == .missing(fileURL))
        #expect(contexts.values.last?.requestGeneration ?? 0 > contexts.values.first?.requestGeneration ?? 0)
    }

    @Test func delayedPriorIdentityUpdateCannotCrossABindingChange() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/epic18/identity-first.md")
        let secondURL = URL(fileURLWithPath: "/tmp/epic18/identity-second.md")
        let firstID = PhysicalFileIdentity.FileObjectID(volume: "v", file: "first")
        let secondID = PhysicalFileIdentity.FileObjectID(volume: "v", file: "second")
        let watcher = MonitorWatcher()
        let prober = RecordingProber()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: watcher,
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )

        try await monitor.bind(to: firstURL, priorFileObjectID: firstID) { _ in }
        try await monitor.bind(to: secondURL, priorFileObjectID: secondID) { _ in }
        await monitor.updateBaseline(priorFileObjectID: firstID, decoding: .automatic, expectedURL: firstURL)
        _ = await monitor.snapshotNow()

        #expect(await prober.lastRequest?.url == secondURL.standardizedFileURL)
        #expect(await prober.lastRequest?.priorFileObjectID == secondID)
    }

    @Test func movedObservationDoesNotRetargetMonitoringBeforeControllerAcceptsIt() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/epic18/proposal-first.md")
        let movedURL = URL(fileURLWithPath: "/tmp/epic18/proposal-moved.md")
        let watcher = MonitorWatcher()
        let initial = snapshot("initial", at: firstURL)
        let moved = snapshot("moved", at: movedURL)
        let prober = ScriptedProber([.available(initial), .moved(moved), .missing(firstURL)])
        let recorder = ObservationRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(to: firstURL, priorFileObjectID: nil) { observation in
            recorder.append(observation)
        }
        await waitUntil { recorder.count == 1 }

        watcher.signal(.changed)
        await waitUntil { recorder.count == 2 }
        _ = await monitor.snapshotNow()

        #expect(await prober.lastExpectedURL == firstURL.standardizedFileURL)
    }

    @Test func realProbeFollowsAProvenSameParentRename() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldURL = directory.appendingPathComponent("before.md")
        let newURL = directory.appendingPathComponent("after.md")
        let store = FileStore()
        _ = try store.write("kept", to: oldURL)
        let prior = try store.readSnapshot(from: oldURL).revision.fileObjectID
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let observation = await DocumentFileProbe(fileStore: store).observe(
            expectedURL: oldURL,
            priorFileObjectID: prior
        )

        #expect(try observation == .moved(store.readSnapshot(from: newURL)))
    }
}

func makeMonitor(watcher: MonitorWatcher, prober: ScriptedProber) -> DocumentFileMonitor {
    DocumentFileMonitor(
        debounce: .zero,
        watcher: watcher,
        prober: prober,
        sleeper: { _ in await Task.yield() }
    )
}

func snapshot(_ text: String, at url: URL) -> FileSnapshot {
    FileSnapshot(
        text: text,
        encoding: .utf8,
        revision: FileRevision(
            url: url.standardizedFileURL,
            modificationDate: .distantPast,
            fileSize: text.utf8.count,
            fileObjectID: nil,
            sha256: text
        )
    )
}

/// Polls against a real wall-clock deadline. The 10 second timeout is only an
/// outer safety bound: a test that needs a particular interleaving must force
/// it (for example with `GateSleeper` or `DeferredProber`) rather than rely on
/// the scheduler reaching it within the timeout. Recorders append
/// synchronously for the same reason (see `DocumentFileMonitorTestSupport`).
func waitUntil(
    _ condition: @escaping @Sendable () async -> Bool,
    timeout: Duration = .seconds(10)
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for asynchronous monitor output")
}

// `ObservationRecorder`, `ContextRecorder`, `HealthRecorder` and
// `GateSleeper` moved to
// `DocumentFileMonitorTestSupport.swift` (shared with the other test files
// in this suite) to stay under swiftlint's file-length budget -- see that
// file for their doc comment explaining why they're lock-based classes
// rather than actors.

/// Tenth review (persistence cross-check #3): the controller advanced its own generation on every `synchronize` but
/// the monitor's only when a bind executed, and the controller required the two to be equal; a superseded (skipped)
/// bind split them permanently. The caller's token is now echoed instead of the monitor's own count.
struct DocumentFileMonitorBindingTokenTests {
    @Test func theCallersBindingTokenIsEchoedInEveryContext() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/token.md")
        let watcher = MonitorWatcher()
        let prober = ScriptedProber([
            .available(snapshot("one", at: fileURL)),
            .available(snapshot("two", at: fileURL)),
        ])
        let contexts = ContextRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)

        // The monitor's own generation is 1 after the first bind and 2 after the second; the tokens are not.
        try await monitor.bind(to: fileURL, priorFileObjectID: nil, onObservation: { _ in },
                               onContext: { contexts.append($0) }, bindingToken: 41)
        await waitUntil { contexts.count == 1 }
        try await monitor.bind(to: fileURL, priorFileObjectID: nil, onObservation: { _ in },
                               onContext: { contexts.append($0) }, bindingToken: 7)
        await waitUntil { contexts.count == 2 }

        #expect(contexts.values.map(\.bindingGeneration) == [41, 7])
    }

    @Test func withoutATokenTheMonitorsOwnGenerationIsUsedAsBefore() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/no-token.md")
        let contexts = ContextRecorder()
        let monitor = makeMonitor(
            watcher: MonitorWatcher(),
            prober: ScriptedProber([.available(snapshot("one", at: fileURL))])
        )

        try await monitor.bind(to: fileURL, priorFileObjectID: nil, onObservation: { _ in },
                               onContext: { contexts.append($0) })
        await waitUntil { contexts.count == 1 }

        #expect(contexts.values.map(\.bindingGeneration) == [1])
    }
}
