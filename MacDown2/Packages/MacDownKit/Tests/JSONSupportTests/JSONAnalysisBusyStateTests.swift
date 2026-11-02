import Foundation
@testable import JSONSupport
import Testing

@MainActor
struct JSONAnalysisBusyStateTests {
    @Test func anOlderCompletionCannotHideANewerImmediateAnalysis() async throws {
        let olderGate = HeldJSONAnalysis()
        let newerGate = HeldJSONAnalysis()
        defer { olderGate.open(); newerGate.open() }
        let session = JSONAnalysisSession(debounce: .milliseconds(1)) {
            $0 == "1" ? olderGate.analyze($0) : newerGate.analyze($0)
        }
        let older = Task { await session.analyzeNow("1") }
        try #require(await olderGate.waitForEntry())
        let newer = Task { await session.analyzeNow("2") }
        try #require(await newerGate.waitForEntry())
        olderGate.open()
        #expect(await older.value.text == "1")
        #expect(session.isAnalyzing)
        #expect(session.result == nil)
        newerGate.open()
        #expect(await newer.value.text == "2")
        #expect(!session.isAnalyzing)
        #expect(session.result?.text == "2")
        #expect(!olderGate.timedOut && !newerGate.timedOut)
    }

    @Test func cancellationKeepsActualImmediateWorkBusyUntilItDrains() async throws {
        let gate = HeldJSONAnalysis()
        defer { gate.open() }
        let session = JSONAnalysisSession(debounce: .milliseconds(1)) { gate.analyze($0) }
        let running = Task { await session.analyzeNow("1") }
        try #require(await gate.waitForEntry())
        session.cancelPending()
        #expect(session.isAnalyzing)
        gate.open()
        #expect(await running.value.text == "1")
        #expect(!session.isAnalyzing)
        #expect(session.result == nil)
        #expect(session.completedAnalysisCount == 0)
        #expect(!gate.timedOut)
    }

    @Test func aNewerResultDoesNotHideAnOlderWorkerStillDraining() async throws {
        let gate = HeldJSONAnalysis()
        defer { gate.open() }
        let session = JSONAnalysisSession(debounce: .milliseconds(1)) {
            $0 == "1" ? gate.analyze($0) : JSONAnalyzer.analyze($0)
        }
        let older = Task { await session.analyzeNow("1") }
        try #require(await gate.waitForEntry())
        #expect(await session.analyzeNow("2").text == "2")
        #expect(session.isAnalyzing)
        #expect(session.result?.text == "2")
        gate.open()
        _ = await older.value
        #expect(!session.isAnalyzing)
        #expect(session.result?.text == "2")
        #expect(!gate.timedOut)
    }
}

private final class HeldJSONAnalysis: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var expired = false

    var timedOut: Bool {
        lock.withLock { expired }
    }

    func analyze(_ text: String) -> JSONAnalysisResult {
        entered.signal()
        let result = release.wait(timeout: .now() + 10)
        lock.withLock { expired = result != .success }
        return JSONAnalyzer.analyze(text)
    }

    func waitForEntry() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: self.entered.wait(timeout: .now() + 5) == .success)
            }
        }
    }

    func open() {
        release.signal()
    }
}
