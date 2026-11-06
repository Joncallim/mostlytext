import AppKit
import FileCore
import Foundation
import LocalResourceAccess
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
@testable import Textual
import Themes

/// The temporary fixture is selected through the test-only receipt; no native panel or persistent grant is used.
@Suite("Secured Markdown mounted attachment", .serialized)
@MainActor
struct SecuredMarkdownMountedTests {
    private let parserIdentity = UUID()

    @Test func aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "![fixture](image.png)"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        var document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        try await installFixtureGrant(folder, for: document, owner: owner)
        let recorder = LoadIDRecorder(imageBytes: imageBytes)
        let initialInput = await PreviewResourceAdmission.shared.globalStatus().retained
        let hosting = NSHostingView(rootView: mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        ))
        let window = makeMountedWindow(hosting: hosting)
        defer {
            owner.close()
            window.orderOut(nil)
            window.close()
        }
        hosting.layoutSubtreeIfNeeded()
        let first = try await waitForLoad(
            after: nil,
            recorder: recorder,
            minimumRetained: initialInput + imageBytes.count
        )
        let originalPasteboard = snapshotPasteboard()
        defer { restorePasteboard(originalPasteboard) }
        try await assertGrantedImageCopies(from: hosting) {
            await recorder.diagnostic(phase: "initial grant")
        }

        document = document.updatingText(source).markClean()
        hosting.rootView = mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        )
        hosting.layoutSubtreeIfNeeded()
        let second = try await waitForLoad(
            after: first, recorder: recorder, minimumRetained: initialInput + imageBytes.count
        )
        #expect(second != first)
        try await assertGrantedImageCopies(from: hosting) {
            await recorder.diagnostic(phase: "new model generation")
        }
        try await assertRevocationStopsCopy(from: hosting, owner: owner, document: document, tabID: tabID)
    }

    @Test func aNewParsedRevisionReplacesTheLoadWithoutAnotherModelEdit() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "![fixture](image.png)"
        let engine = ParseEngine()
        let firstParse = try await engine.parse(source, revision: 1)
        let secondParse = try await engine.parse(source, revision: 2)
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        try await installFixtureGrant(folder, for: document, owner: owner)
        let recorder = LoadIDRecorder(imageBytes: imageBytes)
        let initialInput = await PreviewResourceAdmission.shared.globalStatus().retained
        let hosting = NSHostingView(rootView: mountedView(
            document: document, parsed: firstParse, tabID: tabID, owner: owner, recorder: recorder
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            owner.close()
            window.orderOut(nil)
            window.close()
        }
        let originalPasteboard = snapshotPasteboard()
        defer { restorePasteboard(originalPasteboard) }
        hosting.layoutSubtreeIfNeeded()
        let first = try await waitForLoad(after: nil, recorder: recorder,
                                          minimumRetained: initialInput + imageBytes.count)
        hosting.rootView = mountedView(
            document: document, parsed: secondParse, tabID: tabID, owner: owner, recorder: recorder
        )
        hosting.layoutSubtreeIfNeeded()
        let second = try await waitForLoad(after: first, recorder: recorder,
                                           minimumRetained: initialInput + imageBytes.count)
        #expect(first != second)
        try await assertGrantedImageCopies(from: hosting) {
            await recorder.diagnostic(phase: "new parsed revision")
        }
        #expect(firstParse.sourceSHA256 == secondParse.sourceSHA256)
        #expect(firstParse.revision != secondParse.revision)
    }

    @Test func hidingDuringAParsedFrameReplacementRevokesTheRetainedLoader() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "![fixture](image.png)"
        let engine = ParseEngine()
        let firstParse = try await engine.parse(source, revision: 1)
        let secondParse = try await engine.parse(source, revision: 2)
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        try await installFixtureGrant(folder, for: document, owner: owner)
        let recorder = LoadIDRecorder(imageBytes: imageBytes)
        let initialInput = await PreviewResourceAdmission.shared.globalStatus().retained
        let hosting = NSHostingView(rootView: AnyView(mountedView(
            document: document, parsed: firstParse, tabID: tabID, owner: owner, recorder: recorder
        )))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { owner.close(); window.orderOut(nil); window.close() }
        let originalID = try await waitForLoad(after: nil, recorder: recorder,
                                               minimumRetained: initialInput + imageBytes.count)
        let retained = try #require(recorder.lastLoader)
        let reference = try #require(URL(string: "image.png"))
        let environment = ColorEnvironmentValues(colorScheme: .light, colorSchemeContrast: .standard)
        _ = try await retained.attachment(for: reference, text: "fixture", environment: environment)
        try await hideBeforeReplacementStarts(hosting, next: AnyView(mountedView(
            document: document, parsed: secondParse, tabID: tabID, owner: owner, recorder: recorder
        )), recorder: recorder)
        #expect(recorder.lastID == originalID, "A newer load must not make this retirement control pass")
        do {
            _ = try await retained.attachment(for: reference, text: "fixture", environment: environment)
            Issue.record("A hidden Preview must revoke its previous parsed-frame loader")
        } catch PreviewImageLoadError.denied {
            // The actual retained loader rejects the retired token before a new read.
        } catch PreviewResourceAdmissionError.revoked {
            // A read already entering the admission actor also observes synchronous retirement.
        } catch is CancellationError {
            #expect(!Task.isCancelled, "Only loader retirement, not cancellation of this test, can qualify")
        }
    }

    private func installFixtureGrant(_ folder: URL, for document: FileCore.FileDocument,
                                     owner: PreviewResourceWindowState) async throws {
        let url = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(documentURL: url, folderURL: folder))
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
    }

    private func hideBeforeReplacementStarts(_ host: NSHostingView<AnyView>, next: AnyView,
                                             recorder: LoadIDRecorder) async throws {
        // Do not yield between the new parse publication and removal: its MainActor task must remain pending.
        host.rootView = next
        host.layoutSubtreeIfNeeded()
        #expect(!recorder.didDisappear, "Changing a parse must retain the existing native consumer")
        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !recorder.didDisappear, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(recorder.didDisappear, "The actual mounted Preview must disappear")
    }

    @ViewBuilder
    private func mountedView(
        document: FileCore.FileDocument, parsed: MarkdownDocument, tabID: UUID,
        owner: PreviewResourceWindowState,
        recorder: LoadIDRecorder
    ) -> some View {
        if let frame = PreviewResourceParsedFrame(parserIdentity: parserIdentity, document: parsed) {
            SecuredMarkdownResourceHost(
                tabID: tabID, document: document, sourceGeneration: document.mutationGeneration,
                parsedFrame: frame, publishedText: document.text
            ) { loader, loadID in
                TextualMarkdownPreview(
                    document: parsed, text: document.text,
                    theme: PreviewTheme(theme: BundledThemes.light),
                    resourceImageLoader: loader, resourceLoadID: loadID
                )
                .onChange(of: loadID, initial: true) { _, id in recorder.record(id, loader: loader) }
                .onDisappear { recorder.didDisappear = true }
            }
            .environment(\.previewResourceWindowState, owner)
        }
    }

    private func waitForLoad(
        after prior: UUID?, recorder: LoadIDRecorder, minimumRetained: Int
    ) async throws -> UUID {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let current = recorder.lastID, current != prior,
               await PreviewResourceAdmission.shared.globalStatus().retained >= minimumRetained {
                return current
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let details = await recorder.diagnostic(phase: "load readiness minimumRetained=\(minimumRetained)")
        Issue.record("Mounted Textual did not admit the expected document-bound image; \(details)")
        throw PreviewResourceAdmissionError.limitExceeded
    }
}

@MainActor
private final class LoadIDRecorder {
    private let imageBytes: Data
    private(set) var lastID: UUID?
    private(set) var lastLoader: PreviewResourceImageLoader?
    var didDisappear = false

    init(imageBytes: Data) {
        self.imageBytes = imageBytes
    }

    func diagnostic(phase: String) async -> String {
        let before = await PreviewResourceAdmission.shared.globalStatus()
        let status: String
        if let lastLoader, let reference = URL(string: "image.png") {
            do {
                let environment = ColorEnvironmentValues(colorScheme: .light, colorSchemeContrast: .standard)
                _ = try await lastLoader.attachment(for: reference, text: "fixture", environment: environment)
                status = "actual loader reads and decodes"
            } catch {
                status = "actual loader failed: \(String(reflecting: type(of: error))) \(error)"
            }
        } else {
            status = "no recorded actual loader"
        }
        return "phase=\(phase) loadID=\(String(describing: lastID)) disappeared=\(didDisappear) "
            + "retainedBeforeProbe=\(before.retained) reservedBeforeProbe=\(before.reserved) \(status) "
            + "fixturePNGBase64=\(imageBytes.base64EncodedString())"
            + " observations=\(PreviewResourceDiagnostics.snapshot())"
    }

    func record(_ id: UUID?, loader: PreviewResourceImageLoader? = nil) {
        if let id {
            lastID = id
            if let loader {
                lastLoader = loader
            }
        }
    }
}
