import Foundation
import MarkdownEngine
import Math
@testable import MathRendering
import MathSyntax
import SwiftUIMath
import Testing

struct MathEvaluationTests {
    static let limits = SwiftUIMath.Math.BodyLimits(
        maximumUTF16Length: 16384, maximumDepth: 64, maximumParserSteps: 100_000
    )

    static func request(_ source: String = "$x$", generation: UInt64 = 1) async throws -> MathEvaluationRequest {
        let document = try await ParseEngine().parse(source, revision: Int(generation))
        return MathEvaluationRequest(
            source: source, document: document, sourceIdentity: .init(rawValue: UUID()),
            generation: generation, maximumSpanCount: 512, bodyLimits: limits
        )
    }

    @Test func actualBodyOutcomesRetainOriginalOccurrenceAndExactSource() async throws {
        let request = try await Self.request("$x$ then $\\unknown$ then $y$")
        let value = try request.evaluate()
        #expect(value.analysis.revision == 1)
        #expect(value.analysis.sourceIdentity == request.sourceIdentity)
        #expect(value.entries.map(\.id) == value.analysis.equations.map(\.id))
        #expect(Set(value.entries.map(\.id)).count == 3)
        guard case let .accepted(first) = value.entries[0].outcome,
              case let .rejected(problem) = value.entries[1].outcome,
              case let .accepted(last) = value.entries[2].outcome else {
            Issue.record("Expected independent accepted / actual invalid command / accepted outcomes")
            return
        }
        #expect(first.source == "x")
        #expect(last.source == "y")
        #expect(problem.kind == .unrecognizedCommand)
        #expect(problem.equationID == value.entries[1].id)
        #expect(value.entries[1].equation.syntax.bodyRange.contains(problem.sourceOffset) ||
            problem.sourceOffset == value.entries[1].equation.syntax.bodyRange.upperBound)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func commentAndEmptyBodiesAreAcceptedWithoutGlyphHeuristics(ending: String) async throws {
        let source = "$$% only comment" + ending + "$$\n\n$$\\ $$\n\n$$x%keep" + ending + "+y$$"
        let value = try await Self.request(source).evaluate()
        #expect(value.entries.count == 3)
        for entry in value.entries {
            guard case let .accepted(body) = entry.outcome else {
                Issue.record("Valid comment-only/spacing/math body must not be called malformed")
                continue
            }
            #expect(body.source.utf8.elementsEqual(entry.equation.rendererExpression.utf8))
            #expect(body.limits == Self.limits)
        }
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func diagnosticsMapThroughRemovedContainerPrefixesToTheirOwnSource(ending: String) async throws {
        let source = "> $$x % comment" + ending + "> \\unknown$$"
        let value = try await Self.request(source).evaluate()
        let entry = try #require(value.entries.first)
        guard case let .rejected(problem) = entry.outcome,
              case let .invalid(actual) = try SwiftUIMath.Math.inspectBody(
                  entry.equation.rendererExpression, limits: Self.limits
              ) else {
            Issue.record("Expected the actual engine's invalid command")
            return
        }
        #expect(problem.kind == .unrecognizedCommand)
        #expect(problem.sourceOffset == entry.equation.sourceOffset(forRenderedUTF16Offset: actual.utf16Offset))
        #expect(problem.sourceOffset >= (source as NSString).range(of: "\\unknown", options: .literal).location)
        #expect(problem.sourceOffset <= entry.equation.syntax.bodyRange.upperBound)
    }

    @Test func resourceLimitsAndMalformedSyntaxRemainDifferent() async throws {
        let request = try await Self.request("$abcdef$ ${x$")
        let analysis = try MathAnalysis.analyze(
            source: request.source, document: request.document, sourceIdentity: request.sourceIdentity,
            maximumSpanCount: 512
        )
        let value = try MathEvaluation.evaluate(
            analysis: analysis, limits: .init(maximumUTF16Length: 3, maximumDepth: 64, maximumParserSteps: 100_000)
        )
        let kinds = value.entries.compactMap { entry -> MathEquationDiagnostic.Kind? in
            guard case let .rejected(problem) = entry.outcome else { return nil }
            return problem.kind
        }
        #expect(kinds == [.resourceLimit, .invalidSyntax])
    }

    @Test func cancelledPreparationCannotPublishAPartialSnapshot() async throws {
        let request = try await Self.request("$x$ $y$")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try request.evaluate()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
