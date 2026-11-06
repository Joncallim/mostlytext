import AppKit
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
@testable import Textual
import Themes

@MainActor
@Suite("Secured Markdown source binding", .serialized)
struct SecuredMarkdownSourceBindingTests {
    @Test func canonicallyEquivalentPublishedBytesCannotBorrowTheCurrentGrant() async throws {
        let published = "caf\u{00E9}\n\n![fixture](image.png)\n"
        let current = "cafe\u{0301}\n\n![fixture](image.png)\n"
        #expect(published == current)
        #expect(!published.utf8.elementsEqual(current.utf8))
        let fixture = try PreviewProductionFixture(source: current, previewLayout: .editorOnly)
        defer { fixture.dispose() }
        try await fixture.installGrant()
        let parsed = try await ParseEngine().parse(published, revision: 1)
        let document = try #require(fixture.first.model.activeDocument)
        let recorder = SourceFrameRecorder()
        let host = NSHostingView(rootView: view(document, parsed, published, fixture, recorder))
        let window = fixture.copyHarness.makeMountedWindow(hosting: host)
        defer { window.close() }
        try await fixture.wait("The denied source frame did not apply") { recorder.id != nil }
        try await assertDenied(#require(recorder.loader))
        let deniedID = recorder.id
        let fresh = try await ParseEngine().parse(current, revision: 2)
        host.rootView = view(document, fresh, current, fixture, recorder)
        try await fixture.wait("The exact current source did not replace the denied frame") {
            recorder.id != nil && recorder.id != deniedID
        }
        _ = try await read(#require(recorder.loader))
    }

    @Test func pendingPublishedSourceRetiresThePriorLoadAndKeepsPreviewMounted() async throws {
        let source = "![fixture](image.png)\n"
        let fixture = try PreviewProductionFixture(source: source, previewLayout: .editorOnly)
        defer { fixture.dispose() }
        try await fixture.installGrant()
        let document = try #require(fixture.first.model.activeDocument)
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let recorder = SourceFrameRecorder()
        let host = NSHostingView(rootView: view(document, parsed, source, fixture, recorder))
        let window = fixture.copyHarness.makeMountedWindow(hosting: host)
        defer { window.close() }
        try await fixture.wait("The original bound source frame did not apply") { recorder.id != nil }
        let prior = try #require(recorder.loader)
        _ = try await read(prior)
        let originalID = recorder.id
        host.rootView = view(document, parsed, nil, fixture, recorder)
        try await fixture.wait("Missing published source did not apply a denied frame") {
            recorder.id != nil && recorder.id != originalID
        }
        try await assertDenied(prior)
        try await assertDenied(#require(recorder.loader))
        #expect(fixture.copyHarness.findTextInteraction(in: host) != nil)
        let missingSourceID = recorder.id
        host.rootView = view(document, parsed, source, fixture, recorder)
        try await fixture.wait("Published source arrival did not restore the bound frame") {
            recorder.id != nil && recorder.id != missingSourceID
        }
        _ = try await read(#require(recorder.loader))
    }

    @Test func absentParseRetiresItsPriorLoadWithoutRemovingReadableContent() async throws {
        let source = "![fixture](image.png)\n"
        let fixture = try PreviewProductionFixture(source: source, previewLayout: .editorOnly)
        defer { fixture.dispose() }
        try await fixture.installGrant()
        let document = try #require(fixture.first.model.activeDocument)
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let recorder = SourceFrameRecorder()
        let host = NSHostingView(rootView: view(document, parsed, source, fixture, recorder))
        let window = fixture.copyHarness.makeMountedWindow(hosting: host)
        defer { window.close() }
        try await fixture.wait("The original parsed frame did not apply") { recorder.id != nil }
        let originalID = recorder.id
        let retained = try #require(recorder.loader)
        _ = try await read(retained)
        host.rootView = view(document, nil, source, fixture, recorder,
                             blocks: PreviewBlock.blocks(from: parsed, text: source))
        try await fixture.wait("Missing parse did not apply a denied frame") {
            recorder.id != nil && recorder.id != originalID
        }
        try await assertDenied(retained)
        try await assertDenied(#require(recorder.loader))
        #expect(fixture.copyHarness.findTextInteraction(in: host) != nil)
    }

    private func view(
        _ document: FileCore.FileDocument, _ parsed: MarkdownDocument?, _ published: String?,
        _ fixture: PreviewProductionFixture, _ recorder: SourceFrameRecorder,
        blocks: [PreviewBlock]? = nil
    ) -> some View {
        let frame = parsed.flatMap { PreviewResourceParsedFrame(parserIdentity: recorder.parserIdentity, document: $0) }
        let tabID = fixture.first.model.tabStore.activeTabID ?? UUID()
        return SecuredMarkdownResourceHost(
            tabID: tabID, document: document, sourceGeneration: document.mutationGeneration,
            parsedFrame: frame, publishedText: published
        ) { loader, id in
            TextualMarkdownPreview(document: parsed, text: document.text,
                                   theme: PreviewTheme(theme: BundledThemes.light),
                                   resourceImageLoader: loader, resourceLoadID: id, blocks: blocks)
                .onChange(of: id, initial: true) { _, value in
                    recorder.id = value
                    recorder.loader = loader
                }
        }
        .environment(\.previewResourceWindowState, fixture.first.previewResourceState)
    }

    private func read(_ loader: PreviewResourceImageLoader) async throws -> PreviewImageAttachment {
        let url = try #require(URL(string: "image.png"))
        return try await loader.attachment(for: url, text: "fixture", environment: ColorEnvironmentValues(
            colorScheme: .light, colorSchemeContrast: .standard
        ))
    }

    private func assertDenied(_ loader: PreviewResourceImageLoader) async throws {
        do {
            _ = try await read(loader)
            Issue.record("A stale or absent source frame retained resource authority")
        } catch PreviewImageLoadError.denied {
            // The denied frame has no provider.
        } catch PreviewResourceAdmissionError.revoked {
            // The prior frame's immutable token was retired.
        } catch is CancellationError {
            #expect(!Task.isCancelled, "Only resource retirement, not test cancellation, can qualify")
        }
    }
}

@MainActor
private final class SourceFrameRecorder {
    let parserIdentity = UUID()
    var id: UUID?
    var loader: PreviewResourceImageLoader?
}
