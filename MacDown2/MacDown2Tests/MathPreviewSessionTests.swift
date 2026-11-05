import Foundation
@testable import MacDown2
import MarkdownEngine
import Math
import MathRendering
import Testing

@MainActor
struct MathPreviewSessionTests {
    private final class LiveBox {
        var value: MathPreviewLiveSource?
        init(_ value: MathPreviewLiveSource) {
            self.value = value
        }
    }

    /// Deliberately ignores cancellation to exercise the app's final checks;
    /// physical worker-slot ownership is tested in MathEvaluationWorkerTests.
    private actor Gate {
        var request: MathEvaluationRequest?
        var started: CheckedContinuation<MathEvaluationRequest, Never>?
        var completion: CheckedContinuation<MathEvaluationWorker.Outcome, Never>?

        func compute(_ request: MathEvaluationRequest) async -> MathEvaluationWorker.Outcome {
            self.request = request
            started?.resume(returning: request)
            started = nil
            return await withCheckedContinuation { completion = $0 }
        }

        func waitForRequest() async -> MathEvaluationRequest {
            if let request {
                return request
            }
            return await withCheckedContinuation { started = $0 }
        }

        func finish() throws {
            let request = try #require(request)
            let analysis = try MathAnalysis.analyze(source: request.source, document: request.document,
                                                    sourceIdentity: request.sourceIdentity,
                                                    maximumSpanCount: request.maximumSpanCount)
            let value = try MathEvaluation.evaluate(analysis: analysis, limits: request.bodyLimits)
            completion?.resume(returning: .completed(value))
            completion = nil
        }
    }

    private func live(_ document: MarkdownDocument, source: String,
                      generation: UInt = 1) throws -> MathPreviewLiveSource {
        try .init(
            stamp: .init(tabIdentity: UUID().uuidString, documentID: "file:///tmp/owned.md", recoveryEpoch: UUID(),
                         mutationGeneration: generation, parseIdentity: UUID(), parsedRevision: document.revision,
                         sourceSHA256: #require(document.sourceSHA256)),
            modelText: source,
            editorText: source,
            publishedText: source,
            isKeyWindow: true
        )
    }

    private func locations(_ session: MathPreviewSession) throws -> [UUID: MathPreviewSourceLocation] {
        let evaluation = try #require(session.evaluation)
        var result: [UUID: MathPreviewSourceLocation] = [:]
        for entry in evaluation.entries {
            let offset: Int = switch entry.outcome {
            case let .rejected(problem): problem.sourceOffset
            case .accepted: entry.equation.syntax.bodyRange.lowerBound
            }
            result[entry.id] = .init(range: entry.equation.syntax.fullRange, diagnosticOffset: offset)
        }
        return result
    }

    @Test func actualWorkerPublishesOnlyCurrentEvaluationAndRegistersOwnSourceLocations() async throws {
        let source = "$x$ then $\\unknown$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let box = try LiveBox(live(document, source: source))
        let binding = try MathPreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        let session = MathPreviewSession()
        await session.refresh(binding: binding, document: document, live: { box.value })
        #expect(!session.analysisFailed && session.phase == .preparing)
        #expect(session.evaluation?.entries.count == 2)
        let frame = UUID()
        let own = try locations(session)
        #expect(session.installPresentation(id: frame, bindingID: binding.id, locations: own, live: box.value))
        #expect(!session.isBusy && session.phase == .ready)
        for (id, expected) in own {
            #expect(session.navigationLocation(frameID: frame, sourceID: id, live: box.value) == expected)
        }
        box.value?.isKeyWindow = false
        #expect(try session
            .navigationLocation(frameID: frame, sourceID: #require(own.keys.first), live: box.value) == nil)
    }

    @Test func reopeningTheSamePathDuringAwaitCannotPublishOldMath() async throws {
        let source = "$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let box = try LiveBox(live(document, source: source))
        let binding = try MathPreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        let gate = Gate()
        let session = MathPreviewSession(compute: { await gate.compute($0) })
        let task = Task { await session.refresh(binding: binding, document: document, live: { box.value }) }
        _ = await gate.waitForRequest()
        box.value?.stamp.recoveryEpoch = UUID()
        try await gate.finish()
        await task.value
        #expect(session.evaluation == nil && session.currentFrameID == nil)
        #expect(session.binding == nil && !session.isBusy)
    }

    @Test func lateOldCompletionCannotReplaceANewerCurrentFrame() async throws {
        let first = "$x$", second = "$y$"
        let parser = ParseEngine()
        let oldDocument = try await parser.parse(first, revision: 1)
        let newDocument = try await parser.parse(second, revision: 2)
        let oldLive = try live(oldDocument, source: first)
        var newLive = oldLive
        newLive.stamp.mutationGeneration += 1
        newLive.stamp.parsedRevision = newDocument.revision
        newLive.stamp.sourceSHA256 = try #require(newDocument.sourceSHA256)
        newLive.modelText = second; newLive.editorText = second; newLive.publishedText = second
        let box = LiveBox(oldLive)
        let oldGate = Gate(), newGate = Gate()
        let session = MathPreviewSession(compute: { request in
            if request.generation == 1 {
                return await oldGate.compute(request)
            }
            return await newGate.compute(request)
        })
        let oldBinding = MathPreviewSourceBinding(stamp: oldLive.stamp, source: first)
        let oldTask = Task { await session.refresh(binding: oldBinding, document: oldDocument, live: { box.value }) }
        _ = await oldGate.waitForRequest()
        box.value = newLive
        let newBinding = MathPreviewSourceBinding(stamp: newLive.stamp, source: second)
        let newTask = Task { await session.refresh(binding: newBinding, document: newDocument, live: { box.value }) }
        _ = await newGate.waitForRequest()
        try await newGate.finish()
        await newTask.value
        let frame = UUID(), own = try locations(session)
        #expect(session.installPresentation(id: frame, bindingID: newBinding.id, locations: own, live: box.value))
        try await oldGate.finish()
        await oldTask.value
        #expect(session.currentFrameID == frame && session.binding?.id == newBinding.id)
        #expect(session.evaluation?.entries.first?.equation.rendererExpression == "y")
        #expect(!session.installPresentation(id: UUID(), bindingID: oldBinding.id, locations: [:], live: box.value))
    }

    @Test func aNontextGenerationChangeCanCompleteWithoutReparsingOrPermanentPendingState() async throws {
        let source = "$x$"
        let document = try await ParseEngine().parse(source, revision: 4)
        let box = try LiveBox(live(document, source: source, generation: 7))
        let session = MathPreviewSession()
        let original = try MathPreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        await session.refresh(binding: original, document: document, live: { box.value })
        let oldID = try #require(session.evaluation?.entries.first?.id)
        box.value?.stamp.mutationGeneration += 1
        let saved = try MathPreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        await session.refresh(binding: saved, document: document, live: { box.value })
        #expect(session.evaluation?.analysis.revision == 4)
        #expect(session.evaluation?.entries.first?.id != oldID)
        #expect(try session.installPresentation(
            id: UUID(),
            bindingID: saved.id,
            locations: locations(session),
            live: box.value
        ))
        #expect(!session.isBusy)
    }

    @Test func unpublishedEditorBytesAndCancellationAreRecheckedAfterAwait() async throws {
        let source = "$x$"
        let document = try await ParseEngine().parse(source, revision: 1)
        for cancel in [false, true] {
            let box = try LiveBox(live(document, source: source))
            let binding = try MathPreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
            let gate = Gate()
            let session = MathPreviewSession(compute: { await gate.compute($0) })
            let task = Task { await session.refresh(binding: binding, document: document, live: { box.value }) }
            _ = await gate.waitForRequest()
            if cancel {
                task.cancel()
            } else {
                box.value?.editorText = "$y$"
            }
            try await gate.finish()
            await task.value
            #expect(session.evaluation == nil && session.currentFrameID == nil && !session.isBusy)
        }
    }

    @Test func aFrameCannotRegisterUnknownRangesOrSplitSourceScalarsAndCRLF() async throws {
        let source = "$$😀\r\nx$$"
        let document = try await ParseEngine().parse(source, revision: 1)
        let box = try LiveBox(live(document, source: source))
        let binding = try MathPreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        let session = MathPreviewSession()
        await session.refresh(binding: binding, document: document, live: { box.value })
        let entry = try #require(session.evaluation?.entries.first)
        let own = try locations(session)
        let frame = UUID()
        #expect(session.installPresentation(id: frame, bindingID: binding.id, locations: own, live: box.value))
        for offset in [3, 5] {
            let location = MathPreviewSourceLocation(range: entry.equation.syntax.fullRange,
                                                     diagnosticOffset: offset)
            let invalid = [entry.id: location]
            #expect(!session.installPresentation(
                id: UUID(),
                bindingID: binding.id,
                locations: invalid,
                live: box.value
            ))
        }
        let wrong = [entry.id: MathPreviewSourceLocation(range: 0 ..< 1, diagnosticOffset: 0)]
        #expect(!session.installPresentation(id: UUID(), bindingID: binding.id, locations: wrong, live: box.value))
        let foreign = try [UUID(): #require(own.values.first)]
        #expect(!session.installPresentation(id: UUID(), bindingID: binding.id, locations: foreign, live: box.value))
        #expect(session.currentFrameID == frame)
        #expect(session.navigationLocation(frameID: UUID(), sourceID: entry.id, live: box.value) == nil)
        #expect(session.navigationLocation(frameID: frame, sourceID: UUID(), live: box.value) == nil)
    }
}
