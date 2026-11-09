@testable import FileCore
import Foundation
import Testing

@Suite("Document file monitor watcher ownership")
struct DocumentFileMonitorWatcherOwnershipTests {
    @Test func failedFileWatchCancelsUnadoptedParentOnBindAndExplicitRetry() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/file-watch-failure.md")
        let watcher = MonitorWatcher()
        watcher.failNextFileWatchAttempts(2, code: .EACCES)
        let prober = ScriptedProber([.available(snapshot("initial", at: fileURL))])
        let monitor = makeMonitor(watcher: watcher, prober: prober)

        do {
            try await monitor.bind(to: fileURL, priorFileObjectID: nil) { _ in }
            Issue.record("The injected file-watch failure must fail binding")
        } catch let error as POSIXError {
            #expect(error.code == .EACCES)
        }
        #expect(watcher.watchedDirectories.count == 1)
        #expect(watcher.cancelCount == 1)

        do {
            try await monitor.retryWatching()
            Issue.record("The injected file-watch failure must fail explicit retry")
        } catch let error as POSIXError {
            #expect(error.code == .EACCES)
        }
        #expect(watcher.watchedDirectories.count == 2)
        #expect(watcher.cancelCount == 2)

        try await monitor.retryWatching()
        #expect(watcher.watchedDirectories.count == 3)
        #expect(watcher.cancelCount == 2)
        #expect(await prober.callCount == 1)
        await monitor.cancel()
        #expect(watcher.cancelCount == 3)
    }

    @Test func failedFileWatchCancelsEveryUnadoptedParentRecoveryAttempt() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/epic18/recovery-file-watch-failure.md")
        let watcher = MonitorWatcher()
        let prober = ScriptedProber([
            .available(snapshot("initial", at: fileURL)),
            .available(snapshot("unchanged", at: fileURL)),
        ])
        let health = HealthRecorder()
        let monitor = makeMonitor(watcher: watcher, prober: prober)
        try await monitor.bind(
            to: fileURL,
            priorFileObjectID: nil,
            onObservation: { _ in },
            onHealthChange: { health.append($0) }
        )

        watcher.failNextFileWatchAttempts(4, code: .EACCES)
        watcher.signal(.parentVanished)
        await waitUntil { health.contains(.failed) }

        #expect(watcher.watchedDirectories.count == 5)
        #expect(watcher.cancelCount == 4)
        #expect(await prober.callCount == 2)
        await monitor.cancel()
        #expect(watcher.cancelCount == 5)
    }
}
