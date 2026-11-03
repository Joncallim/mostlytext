@testable import DiagramWebKitPool
import Foundation
import Testing

@MainActor
struct DiagramPoolAdmissionBudgetTests {
    private struct EvaluationWatchdogExceeded: Error {}
    private struct PreparationFailed: Error {}

    @MainActor
    private final class PreparationProbe {
        var page: DiagramHarnessPage?
        var ready = false
        func record(_ page: DiagramHarnessPage) {
            self.page = page
        }

        func markReady() {
            ready = true
        }
    }

    private func makeBundle() throws -> (Bundle, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "<!doctype html><html><body>harness</body></html>".write(
            to: directory.appendingPathComponent("harness.html"), atomically: true, encoding: .utf8
        )
        let bundle = try #require(Bundle(url: directory))
        return (bundle, directory)
    }

    private func makePage() async throws -> (DiagramHarnessPage, URL) {
        let (bundle, directory) = try makeBundle()
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        return (page, directory)
    }

    @Test func preparationFinishesBeforeBorrowingAndUsesAdmissionBudget() async throws {
        let (bundle, directory) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = PreparationProbe()
        let pool = DiagramWebKitPool(
            harnessResourceName: "harness", bundle: bundle, poolSize: 1,
            timeout: .milliseconds(100), admissionTimeout: .seconds(5)
        ) { page in
            await probe.record(page)
            try await Task.sleep(for: .milliseconds(250))
            await probe.markReady()
        }
        let ready = try await pool.withPage { _ in await probe.ready }
        #expect(ready)
        await pool.shutdown()
        #expect(probe.page?.isTerminated == true)
    }

    @Test func preparationFailureRetiresTheUnpublishedPage() async throws {
        let (bundle, directory) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = PreparationProbe()
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1) { page in
            await probe.record(page)
            throw PreparationFailed()
        }
        await #expect(throws: PreparationFailed.self) {
            _ = try await pool.withPage { _ in 42 }
        }
        #expect(probe.page?.isTerminated == true)
        await pool.shutdown()
    }

    @Test func cancelledPreparationRetiresBeforeTheBorrowerReturns() async throws {
        let (bundle, directory) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = PreparationProbe()
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1) { page in
            await probe.record(page)
            try await Task.sleep(for: .seconds(10))
        }
        let borrower = Task { try await pool.withPage { _ in 42 } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.page == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let page = try #require(probe.page)
        borrower.cancel()
        await #expect(throws: CancellationError.self) { try await borrower.value }
        #expect(page.isTerminated)
        await pool.shutdown()
    }

    @Test func coldPageAdmissionHasItsOwnBoundWithoutExtendingEvaluation() async throws {
        let (page, directory) = try await makePage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .milliseconds(100),
            admissionTimeout: .seconds(1)
        ) {
            try await Task.sleep(for: .milliseconds(250))
            return page
        }

        let value = try await pool.withPage { _ in 42 }
        #expect(value == 42)
        await pool.shutdown()
        #expect(page.isTerminated)
    }

    @Test func readyPageDisarmsAdmissionWhileExecutionContinues() async throws {
        let (page, directory) = try await makePage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .seconds(2),
            admissionTimeout: .milliseconds(200)
        ) { page }

        let value = try await pool.withPage { _ in
            try await Task.sleep(for: .milliseconds(500))
            return 42
        }
        #expect(value == 42)
        await pool.shutdown()
        #expect(page.isTerminated)
    }

    @Test func evaluationDeadlineStillWinsAfterReadyPageAdmission() async throws {
        let (page, directory) = try await makePage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .milliseconds(100),
            admissionTimeout: .seconds(1)
        ) { page }

        await #expect(throws: DiagramPoolError.timedOut) {
            _ = try await DiagramTimeoutRace.run(
                timeout: .milliseconds(750),
                timeoutError: EvaluationWatchdogExceeded()
            ) {
                try await pool.withPage { _ in
                    try await Task.sleep(for: .seconds(2))
                    return 43
                }
            }
        }
        await pool.shutdown()
        #expect(page.isTerminated)
    }
}
