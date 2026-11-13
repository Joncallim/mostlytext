@testable import DiagramWebKitPool
import Foundation
import Testing
import WebKit

/// There was no `webViewWebContentProcessDidTerminate` handler anywhere, so a page whose WebContent process died
/// stayed in the pool and every later render through that slot failed until relaunch.
@MainActor
struct DiagramPoolTerminationTests {
    private func makeHarnessBundle() throws -> (bundle: Bundle, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "<!doctype html><html><body>harness</body></html>".write(
            to: directory.appendingPathComponent("harness.html"), atomically: true, encoding: .utf8
        )
        return try (#require(Bundle(url: directory)), directory)
    }

    @Test func aTerminatedPageIsReplacedByTheNextCheckout() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1, timeout: .seconds(30))

        let first = try await pool.withPage { page in
            await MainActor.run {
                // What WebKit calls when the content process dies.
                page.webViewWebContentProcessDidTerminate(WKWebView())
                return page
            }
        }
        let second = try await pool.withPage { page in
            await MainActor.run { (page, page.isTerminated) }
        }

        // Retain the retired page across the second checkout. An identifier
        // alone can be reused at the same address after deallocation.
        #expect(second.0 !== first)
        #expect(second.1 == false)
        await pool.shutdown()
    }

    @Test func aHealthyPageIsReusedAsBefore() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1, timeout: .seconds(30))

        let first = try await pool.withPage { page in await MainActor.run { ObjectIdentifier(page) } }
        let second = try await pool.withPage { page in await MainActor.run { ObjectIdentifier(page) } }

        #expect(first == second)
        await pool.shutdown()
    }

    @Test func queuedRenderCannotReopenAPoolAfterShutdown() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1)
        let entered = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()

        let first = Task {
            try await pool.withPage { _ in
                await entered.fire()
                await release.wait()
            }
        }
        await entered.wait()
        let queued = Task { try await pool.withPage { _ in 42 } }

        await pool.shutdown()
        await release.fire()
        _ = try? await first.value
        do {
            _ = try await queued.value
            Issue.record("a queued request reopened the pool after terminal shutdown")
        } catch {
            #expect(error as? DiagramPoolError == .pageUnavailable)
        }
    }

    @Test func cancellingAQueuedRenderSettlesBeforeItsSlotIsReleased() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1)
        let entered = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()

        let first = Task {
            try await pool.withPage { _ in
                await entered.fire()
                await release.wait()
            }
        }
        await entered.wait()
        let queued = Task { try await pool.withPage { _ in 42 } }
        queued.cancel()

        let outcome: Result<Int, any Error>
        do {
            outcome = try await .success(DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolError.timedOut
            ) { try await queued.value })
        } catch {
            outcome = .failure(error)
        }
        await release.fire()
        _ = try? await first.value
        _ = try? await queued.value
        switch outcome {
        case .success:
            Issue.record("a cancelled request waited for the occupied page")
        case let .failure(error):
            #expect(error is CancellationError)
        }
        await pool.shutdown()
    }

    @Test func queuedRequestDeadlineIncludesPageConstructionWithoutPublishingItsPage() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let constructing = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .milliseconds(100),
            admissionTimeout: .milliseconds(100)
        ) {
            await constructing.fire()
            await release.wait()
            return page
        }

        let first = Task { try await pool.withPage { _ in 1 } }
        await constructing.wait()
        let queued = Task { try await pool.withPage { _ in 2 } }
        do {
            _ = try await DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolTestWatchdog.exceeded
            ) { try await queued.value }
            Issue.record("queued request ran despite an occupied construction slot")
        } catch is DiagramPoolTestWatchdog {
            Issue.record("queued request outlived its request deadline")
        } catch {
            #expect(error as? DiagramPoolError == .timedOut)
        }
        await release.fire()
        _ = try? await first.value
        _ = try? await queued.value
        await pool.shutdown()
        #expect(page.isTerminated)
    }
}

extension DiagramPoolTerminationTests {
    @Test func concurrentShutdownCallersWaitForAnInFlightPageConstruction() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let constructing = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()
        let firstDone = DiagramPoolTestSignal()
        let secondDone = DiagramPoolTestSignal()
        let pool = DiagramWebKitPool(poolSize: 1, timeout: .seconds(30)) {
            await constructing.fire()
            await release.wait()
            return page
        }

        let render = Task { try await pool.withPage { _ in 42 } }
        await constructing.wait()
        let firstShutdown = Task {
            await pool.shutdown()
            await firstDone.fire()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await !(pool.isShuttingDown), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await pool.isShuttingDown)
        let secondShutdown = Task {
            await pool.shutdown()
            await secondDone.fire()
        }
        #expect(await !(firstDone.hasFired))
        #expect(await !(secondDone.hasFired))

        await release.fire()
        await firstShutdown.value
        await secondShutdown.value
        #expect(await firstDone.hasFired)
        #expect(await secondDone.hasFired)
        #expect(page.isTerminated)
        do {
            _ = try await render.value
            Issue.record("construction published a page after shutdown")
        } catch {
            #expect(error as? DiagramPoolError == .pageUnavailable)
        }
    }

    @Test func cancellingDuringPageConstructionTearsDownTheUnpublishedPage() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let constructing = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()
        let pool = DiagramWebKitPool(poolSize: 1, timeout: .seconds(30)) {
            await constructing.fire()
            await release.wait()
            return page
        }

        let render = Task { try await pool.withPage { _ in 42 } }
        await constructing.wait()
        render.cancel()
        await release.fire()
        do {
            _ = try await render.value
            Issue.record("cancelled construction published a page")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(page.isTerminated)
        await pool.shutdown()
    }

    @Test func shutdownTearsDownLivePagesWhileAnotherPageIsStillConstructing() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let livePage = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let constructingPage = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let firstEntered = DiagramPoolTestSignal()
        let releaseFirst = DiagramPoolTestSignal()
        let secondConstructing = DiagramPoolTestSignal()
        let releaseSecond = DiagramPoolTestSignal()
        let factory = DiagramPoolConstructionFactory(
            first: livePage,
            second: constructingPage,
            secondConstructing: secondConstructing,
            releaseSecond: releaseSecond
        )
        let pool = DiagramWebKitPool(poolSize: 2, timeout: .seconds(30)) {
            await factory.make()
        }
        let first = Task {
            try await pool.withPage { _ in
                await firstEntered.fire()
                await releaseFirst.wait()
            }
        }
        await firstEntered.wait()
        let second = Task { try await pool.withPage { _ in 42 } }
        await secondConstructing.wait()
        let shutdown = Task { await pool.shutdown() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !livePage.isTerminated, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(livePage.isTerminated)
        #expect(!constructingPage.isTerminated)
        await releaseSecond.fire()
        await shutdown.value
        #expect(constructingPage.isTerminated)
        await releaseFirst.fire()
        _ = try? await first.value
        _ = try? await second.value
    }
}

extension DiagramPoolTerminationTests {
    @Test func teardownSettlesAnEvaluatingPageBeforeWebKitCompletes() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let evaluation = Task {
            _ = try await page.evaluate("return await new Promise(() => {});", arguments: [:])
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while page.pendingEvaluationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(page.pendingEvaluationCount == 1)
        page.teardown()
        do {
            _ = try await DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolError.timedOut
            ) { try await evaluation.value }
            Issue.record("teardown published a late evaluation")
        } catch {
            #expect(error as? DiagramPoolError == .pageUnavailable)
        }
        #expect(page.pendingEvaluationCount == 0)
    }

    @Test func cancellationSettlesAnEvaluatingPageWithoutWaitingForJavaScript() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let evaluation = Task {
            _ = try await page.evaluate("return await new Promise(() => {});", arguments: [:])
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while page.pendingEvaluationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(page.pendingEvaluationCount == 1)
        evaluation.cancel()
        do {
            _ = try await DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolError.timedOut
            ) { try await evaluation.value }
            Issue.record("cancellation waited for the unending JavaScript promise")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(page.pendingEvaluationCount == 0)
        page.teardown()
    }
}

private actor DiagramPoolTestSignal {
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    var hasFired: Bool {
        fired
    }

    func wait() async {
        if fired {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func fire() {
        fired = true
        waiter?.resume()
        waiter = nil
    }
}

private actor DiagramPoolConstructionFactory {
    let first: DiagramHarnessPage
    let second: DiagramHarnessPage
    let secondConstructing: DiagramPoolTestSignal
    let releaseSecond: DiagramPoolTestSignal
    var calls = 0

    init(
        first: DiagramHarnessPage,
        second: DiagramHarnessPage,
        secondConstructing: DiagramPoolTestSignal,
        releaseSecond: DiagramPoolTestSignal
    ) {
        self.first = first
        self.second = second
        self.secondConstructing = secondConstructing
        self.releaseSecond = releaseSecond
    }

    func make() async -> DiagramHarnessPage {
        calls += 1
        if calls == 1 {
            return first
        }
        await secondConstructing.fire()
        await releaseSecond.wait()
        return second
    }
}

private enum DiagramPoolTestWatchdog: Error {
    case exceeded
}
