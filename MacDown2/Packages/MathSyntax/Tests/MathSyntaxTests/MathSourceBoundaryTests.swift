import Foundation
import MathSyntax
import Testing

@Suite("Math syntax structural/literal source boundaries")
struct MathSourceBoundaryTests {
    @Test func regionsStaySeparateEvenWhenTheyTouch() throws {
        let source = "$x$"
        #expect(try MathSyntaxTestSupport.scan(source, regions: [0 ..< 1, 1 ..< 3]).spans.isEmpty)
        let two = "$a$ and $b$"
        let result = try MathSyntaxTestSupport.scan(two, regions: [8 ..< 11, 0 ..< 3])
        try MathSyntaxTestSupport.expect(
            result,
            source: two,
            tokens: [.init("$a$", "a", .inline), .init("$b$", "b", .inline)]
        )
    }

    @Test func excludedLiteralSourceCannotPairWithProse() throws {
        let source = "$bad$ and $ok$"
        let result = try MathSyntaxTestSupport.scan(source, exclusions: [2 ..< 3])
        try MathSyntaxTestSupport.expect(result, source: source, tokens: [.init("$ok$", "ok", .inline)])
        let code = "`$literal$` then $x$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(code, exclusions: [0 ..< 11]), source: code,
                                         tokens: [.init("$x$", "x", .inline)])
    }

    @Test func exclusionsMergeAndCanSpanSeveralRegions() throws {
        let source = "$a$.$b$.$c$"
        let result = try MathSyntaxTestSupport.scan(source, regions: [0 ..< 4, 4 ..< 8, 8 ..< 11],
                                                    exclusions: [5 ..< 7, 3 ..< 6, 7 ..< 8])
        try MathSyntaxTestSupport.expect(
            result,
            source: source,
            tokens: [.init("$a$", "a", .inline), .init("$c$", "c", .inline)]
        )
        #expect(try MathSyntaxTestSupport.scan(source, regions: [0 ..< 4, 4 ..< 8, 8 ..< 11],
                                               exclusions: [1 ..< 9]).spans.isEmpty)
    }

    @Test func malformedMetadataFailsBeforeTokenization() throws {
        #expect(throws: MathSyntaxError.invalidRegion) { try MathSyntaxTestSupport.scan("abc", regions: [-1 ..< 1]) }
        #expect(throws: MathSyntaxError.invalidRegion) { try MathSyntaxTestSupport.scan("abc", regions: [0 ..< 4]) }
        #expect(throws: MathSyntaxError.overlappingRegions) {
            try MathSyntaxTestSupport.scan("abc", regions: [0 ..< 2, 1 ..< 3])
        }
        #expect(throws: MathSyntaxError.invalidExclusion) {
            try MathSyntaxTestSupport.scan("abc", exclusions: [(Int.max - 1) ..< Int.max])
        }
        #expect(throws: MathSyntaxError.invalidRegion) { try MathSyntaxTestSupport.scan("😀$x$", regions: [0 ..< 1]) }
        #expect(throws: MathSyntaxError.invalidExclusion) {
            try MathSyntaxTestSupport.scan("😀$x$", exclusions: [1 ..< 2])
        }
    }

    @Test func sourceSnapshotIdentityAndRepeatedOccurrencesRemainDistinct() throws {
        let identity = MathSourceIdentity(rawValue: UUID())
        let source = "$x$ and $x$"
        let result = try MathSyntaxTestSupport.scan(source, identity: identity)
        try #require(result.spans.count == 2)
        #expect(result.spans.allSatisfy { $0.sourceIdentity == identity })
        #expect(result.spans[0].fullRange != result.spans[1].fullRange)
        let newer = try MathSyntaxTestSupport.scan(source)
        #expect(result.spans[0].sourceIdentity != newer.spans[0].sourceIdentity)
    }

    @Test func limitsReportTheLiteralTailWithoutASecondMathPass() throws {
        let source = "$a$ and $b$"
        let result = try MathSyntaxTestSupport.scan(source, maximumSpanCount: 1)
        #expect(result.spans.count == 1)
        #expect(result.literalRemainderOffset == 3)
        let zero = try MathSyntaxTestSupport.scan(source, maximumSpanCount: 0)
        #expect(zero.spans.isEmpty)
        #expect(zero.literalRemainderOffset == 0)
        #expect(try MathSyntaxTestSupport.scan("$a$", maximumSpanCount: 1).literalRemainderOffset == nil)
        #expect(throws: MathSyntaxError.invalidMaximumSpanCount) {
            try MathSyntaxTestSupport.scan(source, maximumSpanCount: -1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func longDollarRunHasBoundedForwardWork() throws {
        let source = String(repeating: "$", count: 100_000)
        let result = try MathSyntaxTestSupport.scan(source, maximumSpanCount: 20001)
        #expect(result.spans.count == 20000)
        #expect(result.spans.first?.fullRange == 0 ..< 5)
        #expect(result.spans.last?.fullRange == 99995 ..< 100_000)
        #expect(result.literalRemainderOffset == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cancellationPreventsQueuedLexing() async throws {
        let gate = MathLexingCancellationGate()
        let operation = Task {
            await gate.suspend()
            return try MathSyntaxTestSupport.scan("$x$")
        }
        defer { gate.release() }
        var iterator = gate.ready.stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        operation.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
    }
}

@MainActor
private final class MathLexingCancellationGate {
    let ready = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            ready.continuation.yield(())
        }
    }

    func release() {
        let suspended = continuation
        continuation = nil
        suspended?.resume()
    }
}
