import FileCore
import Foundation
@testable import MacDown2
import Testing
import WebKit

@MainActor
extension HTMLPreviewNavigationIdentityTests {
    @Test func lowerGenerationNewDocumentClearsOldAuthorityAndLoadsItsOwnDirectory() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        fixture.document = fixture.document.markClean().markClean()
        let oldNavigation = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)
        let handler = try #require(fixture.view.configuration.urlSchemeHandler(forURLScheme: "macdown-preview")
            as? PreviewSchemeHandler)
        let oldURL = try #require(handler.mainURL)

        let destination = fixture.directory.appendingPathComponent("new-document", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let newDocument = FileDocument(fileURL: destination.appendingPathComponent("second.html"), text: "new")
        #expect(newDocument.mutationGeneration < fixture.document.mutationGeneration)
        fixture.coordinator.preview(document: newDocument, in: fixture.view)
        #expect(fixture.view.isHidden)
        #expect(fixture.view.loads.count == 2, "the prior document is cleared before the debounce")
        #expect(handler.request?.source == "")
        #expect(handler.request?.baseURL == nil)
        #expect(handler.mainURL != oldURL)

        let newNavigation = try await fixture.waitForLoad(count: 3)
        #expect(handler.request?.source == "new")
        #expect(handler.request?.baseURL == destination)
        #expect(fixture.coordinator.gate.pendingGeneration == 0)
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)
        #expect(fixture.coordinator.gate.pendingGeneration == 0)
        fixture.coordinator.webView(fixture.view, didFinish: newNavigation)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == 0)
        #expect(!fixture.view.isHidden)
        fixture.coordinator.preview(document: newDocument.edited(text: "unsaved edit"), in: fixture.view)
        #expect(!fixture.view.isHidden, "dirty edits within the same document retain its last saved page")
    }

    @Test func dirtyNewDocumentClearsOldPageWithoutRenderingUnsavedSource() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        fixture.document = fixture.document.markClean().markClean()
        let oldNavigation = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)
        let handler = try #require(fixture.view.configuration.urlSchemeHandler(forURLScheme: "macdown-preview")
            as? PreviewSchemeHandler)
        let oldURL = try #require(handler.mainURL)

        let dirtyDocument = FileDocument(text: "other").edited(text: "unsaved")
        fixture.coordinator.preview(document: dirtyDocument, in: fixture.view)
        #expect(fixture.view.isHidden)
        #expect(fixture.view.loads.count == 2, "a new dirty document gets a blank page")
        #expect(handler.request?.source == "")
        #expect(handler.request?.baseURL == nil)
        #expect(handler.mainURL != oldURL)
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.view.reloads.isEmpty)
    }

    @Test func refusedBlankNavigationKeepsPriorDocumentHidden() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let oldNavigation = try await fixture.startNextRevision()
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)

        fixture.view.returnNilFromLoad = true
        let dirtyDocument = FileDocument(text: "other").edited(text: "unsaved")
        fixture.coordinator.preview(document: dirtyDocument, in: fixture.view)
        #expect(fixture.view.loads.count == 2)
        #expect(fixture.view.loads[1] == nil)
        #expect(fixture.view.isHidden)
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)
        #expect(fixture.view.isHidden)
    }

    @Test func failedBlankNavigationKeepsPriorDocumentHidden() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let oldNavigation = try await fixture.startNextRevision()
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)

        let dirtyDocument = FileDocument(text: "other").edited(text: "unsaved")
        fixture.coordinator.preview(document: dirtyDocument, in: fixture.view)
        let blankNavigation = try #require(fixture.view.loads[1])
        fixture.coordinator.webView(
            fixture.view, didFailProvisionalNavigation: blankNavigation, withError: fixture.failure()
        )
        #expect(fixture.view.isHidden)
        fixture.coordinator.webView(fixture.view, didFinish: oldNavigation)
        #expect(fixture.view.isHidden)
    }

    @Test func distinctTabIdentityCannotReuseTheSameGenerationPage() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        fixture.document = fixture.document.markClean()
        fixture.coordinator.preview(document: fixture.document, tabID: UUID(), in: fixture.view)
        let first = try await fixture.waitForLoad(count: 1)
        fixture.coordinator.webView(fixture.view, didFinish: first)
        let handler = try #require(fixture.view.configuration.urlSchemeHandler(forURLScheme: "macdown-preview")
            as? PreviewSchemeHandler)
        let oldURL = try #require(handler.mainURL)

        fixture.coordinator.preview(document: fixture.document, tabID: UUID(), in: fixture.view)
        #expect(fixture.view.loads.count == 2)
        #expect(handler.request?.source == "")
        #expect(handler.mainURL != oldURL)
        _ = try await fixture.waitForLoad(count: 3)
        #expect(handler.request?.source == fixture.document.text)
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
    }
}
