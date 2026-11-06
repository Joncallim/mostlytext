import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HeadingPreviewSessionTests {
    private final class LiveBox {
        var value: PreviewLiveSource?
        init(_ value: PreviewLiveSource) {
            self.value = value
        }
    }

    /// Ignores cancellation to exercise the session's final authority check.
    /// The real worker's physical bounds have separate package controls.
    private actor Gate {
        var request: HeadingPreparationRequest?
        var observer: CheckedContinuation<HeadingPreparationRequest, Never>?
        var completion: CheckedContinuation<HeadingPreparationWorker.Outcome, Never>?

        func compute(_ request: HeadingPreparationRequest) async -> HeadingPreparationWorker.Outcome {
            self.request = request
            observer?.resume(returning: request)
            observer = nil
            return await withCheckedContinuation { completion = $0 }
        }

        func waitForRequest() async -> HeadingPreparationRequest {
            if let request {
                return request
            }
            return await withCheckedContinuation { observer = $0 }
        }

        func finish() async throws {
            let request = try #require(request)
            let value = try await HeadingAnchorPreparation.prepare(
                document: request.document, sourceText: request.sourceText, documentID: request.documentID,
                recoveryEpoch: request.recoveryEpoch, sourceGeneration: request.sourceGeneration
            )
            completion?.resume(returning: .completed(value))
            completion = nil
        }

        func cancel() {
            completion?.resume(returning: .cancelled)
            completion = nil
        }
    }

    @Test func theActualWorkerPublishesTheOriginalIndexAndRequiresKeyWindowAuthority() async throws {
        let source = "# A\n\n# A\n\n# Café\n"
        let document = try await ParseEngine().parse(source, revision: 4)
        let box = try LiveBox(live(document, source: source))
        let binding = try PreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        let session = HeadingPreviewSession()
        await session.refresh(binding: binding, document: document, live: { box.value })
        let preparation = try #require(session.currentPreparation(live: box.value))
        #expect(preparation.index.headings.map(\.fragment) == ["a", "a-1", "café"])
        #expect(session.phase == .ready && session.publicationID == binding.id)
        let heading = try #require(preparation.index.headings.last)
        #expect(session.navigationHeading(bindingID: binding.id, heading: heading,
                                          identity: preparation.index.identity, live: box.value) == heading)
        box.value?.isKeyWindow = false
        #expect(session.currentPreparation(live: box.value) != nil)
        #expect(session.navigationHeading(bindingID: binding.id, heading: heading,
                                          identity: preparation.index.identity, live: box.value) == nil)
    }

    @Test(arguments: ["recovery", "parser", "generation", "editor", "model", "published", "cancel"])
    func changedAuthorityDuringPreparationCannotPublish(_ change: String) async throws {
        let source = "# Target\n"
        let document = try await ParseEngine().parse(source, revision: 4)
        let box = try LiveBox(live(document, source: source))
        let binding = try PreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        let gate = Gate()
        let session = HeadingPreviewSession(compute: { await gate.compute($0) })
        let task = Task { await session.refresh(binding: binding, document: document, live: { box.value }) }
        defer { task.cancel(); Task { await gate.cancel() } }
        _ = await gate.waitForRequest()
        switch change {
        case "recovery": box.value?.stamp.recoveryEpoch = UUID()
        case "parser": box.value?.stamp.parseIdentity = UUID()
        case "generation": box.value?.stamp.mutationGeneration += 1
        case "editor": box.value?.editorText = "# Other\n"
        case "model": box.value?.modelText = "# Other\n"
        case "published": box.value?.publishedText = "# Other\n"
        default: task.cancel()
        }
        try await gate.finish()
        await task.value
        #expect(session.preparation == nil && session.binding == nil && session.phase == .idle)
    }

    @Test func sameSourceAndIndexIdentityCannotAuthorizeAnOldParserBindingsAction() async throws {
        let source = "# Target\n"
        let document = try await ParseEngine().parse(source, revision: 4)
        let box = try LiveBox(live(document, source: source))
        let original = try PreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        let session = HeadingPreviewSession()
        await session.refresh(binding: original, document: document, live: { box.value })
        let old = try #require(session.preparation)
        let heading = try #require(old.index.headings.first)
        box.value?.stamp.parseIdentity = UUID()
        let replacement = try PreviewSourceBinding(stamp: #require(box.value?.stamp), source: source)
        await session.refresh(binding: replacement, document: document, live: { box.value })
        #expect(session.preparation?.index.identity == old.index.identity)
        #expect(session.navigationHeading(bindingID: original.id, heading: heading,
                                          identity: old.index.identity, live: box.value) == nil)
        #expect(session.navigationHeading(bindingID: replacement.id, heading: heading,
                                          identity: old.index.identity, live: box.value) == heading)
    }

    @Test func aLateOldCompletionCannotReplaceTheNewerPublishedHeadingIndex() async throws {
        let parser = ParseEngine()
        let oldDocument = try await parser.parse("# Old\n", revision: 4)
        let newDocument = try await parser.parse("# New\n", revision: 5)
        let box = try LiveBox(live(oldDocument, source: "# Old\n"))
        let original = try PreviewSourceBinding(stamp: #require(box.value?.stamp), source: "# Old\n")
        let gate = Gate()
        let session = HeadingPreviewSession(compute: { request in
            if request.sourceGeneration == 1 {
                return await gate.compute(request)
            }
            do {
                return try await .completed(HeadingAnchorPreparation.prepare(
                    document: request.document, sourceText: request.sourceText, documentID: request.documentID,
                    recoveryEpoch: request.recoveryEpoch, sourceGeneration: request.sourceGeneration
                ))
            } catch { return .failed(error) }
        })
        let task = Task { await session.refresh(binding: original, document: oldDocument, live: { box.value }) }
        defer { task.cancel(); Task { await gate.cancel() } }
        _ = await gate.waitForRequest()
        box.value?.stamp.mutationGeneration = 2
        box.value?.stamp.parsedRevision = 5
        box.value?.stamp.sourceSHA256 = try #require(newDocument.sourceSHA256)
        box.value?.modelText = "# New\n"; box.value?.editorText = "# New\n"; box.value?.publishedText = "# New\n"
        let replacement = try PreviewSourceBinding(stamp: #require(box.value?.stamp), source: "# New\n")
        await session.refresh(binding: replacement, document: newDocument, live: { box.value })
        try await gate.finish()
        await task.value
        #expect(session.binding?.id == replacement.id && session.preparation?.index.headings.first?.title == "New")
    }

    private func live(_ document: MarkdownDocument, source: String) throws -> PreviewLiveSource {
        try .init(stamp: .init(
            tabIdentity: UUID().uuidString, documentID: "own", recoveryEpoch: UUID(), mutationGeneration: 1,
            parseIdentity: UUID(), parsedRevision: document.revision, sourceSHA256: #require(document.sourceSHA256)
        ), modelText: source, editorText: source, publishedText: source, isKeyWindow: true)
    }
}
