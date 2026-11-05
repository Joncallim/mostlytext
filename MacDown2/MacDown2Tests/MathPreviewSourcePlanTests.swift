import Foundation
@testable import MacDown2
import MarkdownEngine
import Math
import MathRendering
import Preview
import Testing

@MainActor
struct MathPreviewSourcePlanTests {
    private func request(_ source: String) async throws -> MathPreviewSourceRequest {
        let document = try await ParseEngine().parse(source, revision: 1)
        let analysis = try MathAnalysis.analyze(source: source, document: document,
                                                sourceIdentity: .init(rawValue: UUID()), maximumSpanCount: 512)
        let evaluation = try MathEvaluation.evaluate(
            analysis: analysis,
            limits: MathProcessingPolicy.standard.bodyLimits
        )
        return try .init(source: source, document: document, blocks: PreviewBlock.blocks(from: document, text: source),
                         evaluation: evaluation, presentation: MathPresentationPlan(
                             evaluation: evaluation,
                             document: document
                         ))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func actualAuthoredBlocksReceiveOnlyTheirOwnRepairedReferenceInput(_ ending: String) async throws {
        let source = "> - [$x$][]\n\n[$x$]: /right \"title\"\n\n[other](/else)".replacingOccurrences(
            of: "\n",
            with: ending
        )
        let request = try await request(source)
        let plan = try await MathPreviewSourcePlanner.prepare(request)
        let block = try #require(request.blocks.first)
        guard case let .parsed(input)? = plan.blocks[block.id] else {
            Issue.record("Expected a proven original block input")
            return
        }
        #expect(input.source.utf8.elementsEqual(block.source.utf8))
        #expect(plan.drawableEntries.map(\.equation.rendererExpression) == ["x"])
        let replay = try await ParseEngine().parse(input.rewritten, revision: 2)
        #expect(replay.sourceFacts?.links.map(\.destination) == ["/right"])
        #expect(replay.sourceFacts?.links.map(\.title) == ["title"])
        #expect(plan.locations.first?.value.range == request.evaluation.entries.first?.equation.syntax.fullRange)
    }

    @Test func generatedMatchingTextCannotAcquireAuthoredMathAuthority() async throws {
        let source = "$x$"
        let original = try await request(source)
        let generated = PreviewBlock(kind: .paragraph, source: source, lineRange: 1 ... 1)
        let request = MathPreviewSourceRequest(source: source, document: original.document, blocks: [generated],
                                               evaluation: original.evaluation, presentation: original.presentation)
        let plan = try await MathPreviewSourcePlanner.prepare(request)
        #expect(plan.blocks[generated.id] == nil)
        #expect(plan.drawableEntries.isEmpty)
    }

    @Test func definitionsAndMarkersMustFitTogetherBeforeNativeParsing() async throws {
        let source = "[key]: /" + String(repeating: "q", count: 65500) + "\n\n[$x$][key]"
        let request = try await request(source)
        let plan = try await MathPreviewSourcePlanner.prepare(request)
        let block = try #require(request.blocks.first)
        #expect(!block.isOversize)
        #expect(request.evaluation.entries.count == 1)
        guard case .literal? = plan.blocks[block.id] else {
            Issue.record("Expanded prefix/marker overflow must retain authored text")
            return
        }
        #expect(plan.drawableEntries.isEmpty)
        #expect(plan.notices.first?.kind == .resourceLimit)
    }

    @Test func anOriginSlicedThroughASurrogateCannotBeRepairedIntoSourceAuthority() async throws {
        let source = "😀 $x$"
        let original = try await request(source)
        let block = try #require(original.blocks.first)
        let anchor = try #require(block.sourceAnchor?.slice(1 ..< source.utf16.count))
        let brokenText = (source as NSString).substring(from: 1)
        let broken = PreviewBlock(
            kind: block.kind,
            source: brokenText,
            lineRange: block.lineRange,
            sourceAnchor: anchor
        )
        let request = MathPreviewSourceRequest(source: source, document: original.document, blocks: [broken],
                                               evaluation: original.evaluation, presentation: original.presentation)
        let plan = try await MathPreviewSourcePlanner.prepare(request)
        guard case .literal? = plan.blocks[broken.id] else {
            Issue.record("An interior original UTF-16 endpoint cannot authorize native substitutions")
            return
        }
        #expect(plan.drawableEntries.isEmpty)
    }
}
