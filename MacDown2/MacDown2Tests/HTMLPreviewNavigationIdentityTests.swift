import FileCore
import Foundation
@testable import MacDown2
import Testing
import WebKit

/// The real coordinator receives explicitly ordered callbacks. Local blank pages provide valid WebKit
/// navigation objects; these checks prove delegate ownership, not native scheduling or containment.
@MainActor
struct HTMLPreviewNavigationIdentityTests {
    @Test func lateFinishCannotCompleteANewerLoadOrPreventItsRetry() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let old = try await fixture.startNextRevision()
        let current = try await fixture.startNextRevision()
        let generation = fixture.document.mutationGeneration

        fixture.coordinator.webView(fixture.view, didFinish: old)
        #expect(fixture.coordinator.gate.pendingGeneration == generation)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == nil)

        fixture.coordinator.webView(fixture.view, didFail: current, withError: fixture.failure())
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        let retry = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: retry)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == generation)
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
    }

    @Test(arguments: [false, true])
    func lateFailureCannotRearmANewerLoad(provisional: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let old = try await fixture.startNextRevision()
        let current = try await fixture.startNextRevision()
        if provisional {
            fixture.coordinator.webView(fixture.view, didFailProvisionalNavigation: old, withError: fixture.failure())
        } else {
            fixture.coordinator.webView(fixture.view, didFail: old, withError: fixture.failure())
        }
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webView(fixture.view, didFinish: current)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func nilUnknownAndWrongViewCallbacksCannotSettleTheCurrentLoad() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let current = try await fixture.startNextRevision()
        let otherView = RecordedWebView()
        defer { otherView.stopLoading() }
        let unknown = try #require(otherView.loadHTMLString("<!doctype html><title>fixture</title>", baseURL: nil))
        for navigation in [nil, unknown] {
            fixture.coordinator.webView(fixture.view, didFinish: navigation)
            fixture.coordinator.webView(fixture.view, didFail: navigation, withError: fixture.failure())
            fixture.coordinator.webView(
                fixture.view,
                didFailProvisionalNavigation: navigation,
                withError: fixture.failure()
            )
        }
        fixture.coordinator.webView(otherView, didFinish: current)
        fixture.coordinator.webView(otherView, didFail: current, withError: fixture.failure())
        fixture.coordinator.webViewWebContentProcessDidTerminate(otherView)
        #expect(otherView.reloads.isEmpty)
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webView(fixture.view, didFinish: current)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func disposalRevokesOwnershipBeforeStoppingWebKit() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let navigation = try await fixture.startNextRevision()
        fixture.view.onStop = {
            fixture.coordinator.webView(fixture.view, didFinish: navigation)
            fixture.coordinator.webView(fixture.view, didFail: navigation, withError: fixture.failure())
        }
        fixture.coordinator.dispose(webView: fixture.view)
        fixture.view.onStop = nil
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == nil)
        #expect(fixture.view.reloads.isEmpty)
    }

    @Test func aQueuedNewerRevisionIsNotAssignedToARecoveryOfTheOldPage() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let old = try await fixture.startNextRevision()
        fixture.document = fixture.document.markClean()
        // No actor suspension between scheduling B and reporting A's process termination.
        fixture.coordinator.preview(document: fixture.document, in: fixture.view)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.view.reloads.isEmpty)
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        let current = try await fixture.waitForLoad(count: 2)
        fixture.coordinator.webView(fixture.view, didFinish: old)
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webView(fixture.view, didFinish: current)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func recoveryHasItsOwnNavigationAndKeepsTheCrashBudget() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let original = try await fixture.startNextRevision()
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        let recovery = try #require(fixture.view.reloads.first ?? nil)
        fixture.coordinator.webView(fixture.view, didFinish: original)
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webView(fixture.view, didFinish: recovery)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.view.reloads.count == 1)
    }

    @Test func aCancelledQueuedRevisionDoesNotBlockRecoveryOfTheDisplayedPage() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let original = try await fixture.startNextRevision()
        let displayedGeneration = fixture.document.mutationGeneration
        fixture.coordinator.webView(fixture.view, didFinish: original)
        fixture.document = fixture.document.markClean()
        let cancelledGeneration = fixture.document.mutationGeneration
        fixture.coordinator.preview(document: fixture.document, in: fixture.view)
        fixture.document = fixture.document.edited(text: "unsaved edit")
        fixture.coordinator.preview(document: fixture.document, in: fixture.view)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        let recovery = try #require(fixture.view.reloads.first ?? nil)
        fixture.coordinator.webView(fixture.view, didFinish: recovery)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == displayedGeneration)
        #expect(fixture.coordinator.gate.pendingGeneration == cancelledGeneration)
        let nextSaved = try await fixture.startNextRevision()
        #expect(fixture.view.loads.count == 2)
        fixture.coordinator.webView(fixture.view, didFinish: nextSaved)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func aQueuedSameGenerationRetryKeepsItsOwnAdmissionDuringProcessTermination() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        let original = try await fixture.startNextRevision()
        fixture.coordinator.webView(fixture.view, didFail: original, withError: fixture.failure())
        // Queue B(g) and report termination without allowing its debounce task to enter beginLoad.
        fixture.coordinator.preview(document: fixture.document, in: fixture.view)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.view.reloads.isEmpty)
        if let recovery = fixture.view.reloads.first ?? nil {
            fixture.coordinator.webView(fixture.view, didFinish: recovery)
        }
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        let retry = try await fixture.waitForLoad(count: 2)
        fixture.coordinator.webView(fixture.view, didFail: retry, withError: fixture.failure())
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == nil)
        let finalRetry = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: finalRetry)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func aFailedPendingRecoveryCanRetryAndItsLateCallbackCannotSettleTheRetry() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        _ = try await fixture.startNextRevision()
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        let recovery = try #require(fixture.view.reloads.first ?? nil)
        fixture.coordinator.webView(fixture.view, didFail: recovery, withError: fixture.failure())
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        let retry = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: recovery)
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webView(fixture.view, didFinish: retry)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func aRecoveryCallbackCannotSettleANewerStartedRevision() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        _ = try await fixture.startNextRevision()
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        let recovery = try #require(fixture.view.reloads.first ?? nil)
        let newer = try await fixture.startNextRevision()
        fixture.coordinator.webView(fixture.view, didFinish: recovery)
        fixture.coordinator.webView(fixture.view, didFail: recovery, withError: fixture.failure())
        #expect(fixture.coordinator.gate.pendingGeneration == fixture.document.mutationGeneration)
        fixture.coordinator.webView(fixture.view, didFinish: newer)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func aNilLoadReturnRearmsOnlyThatAttempt() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        fixture.document = fixture.document.markClean()
        fixture.view.returnNilFromLoad = true
        fixture.coordinator.preview(document: fixture.document, in: fixture.view)
        await fixture.waitForAttempt(count: 1)
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        fixture.view.returnNilFromLoad = false
        let retry = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: retry)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

    @Test func aNilPendingRecoveryRearmsWithoutRestoringItsBudget() async throws {
        let fixture = Fixture()
        defer { fixture.dispose() }
        _ = try await fixture.startNextRevision()
        fixture.view.returnNilFromReload = true
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.view.reloads.count == 1)
        let retry = try await fixture.startCurrentRevision()
        fixture.coordinator.webView(fixture.view, didFinish: retry)
        #expect(fixture.coordinator.gate.lastLoadedGeneration == fixture.document.mutationGeneration)
    }

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
        #expect(fixture.view.loads.count == 2, "a new dirty document gets a blank page")
        #expect(handler.request?.source == "")
        #expect(handler.request?.baseURL == nil)
        #expect(handler.mainURL != oldURL)
        #expect(fixture.coordinator.gate.pendingGeneration == nil)
        fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
        #expect(fixture.view.reloads.isEmpty)
    }
}

extension HTMLPreviewNavigationIdentityTests {
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

    @MainActor
    private final class Fixture {
        let coordinator = HTMLPreviewView.Coordinator(reloadDelay: .zero)
        let view = RecordedWebView()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document: FileDocument

        init() {
            document = FileDocument(text: "fixture", recoveryBuffer: RecoveryBuffer(recoveryDirectory: directory))
        }

        func startNextRevision() async throws -> WKNavigation {
            document = document.markClean()
            return try await startCurrentRevision()
        }

        func startCurrentRevision() async throws -> WKNavigation {
            let count = view.loads.count + 1
            coordinator.preview(document: document, in: view)
            return try await waitForLoad(count: count)
        }

        func waitForAttempt(count: Int) async {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while view.loads.count < count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(view.loads.count == count, "fixture did not reach the load boundary")
        }

        func waitForLoad(count: Int) async throws -> WKNavigation {
            await waitForAttempt(count: count)
            try #require(view.loads.count == count)
            return try #require(view.loads[count - 1])
        }

        func failure() -> NSError {
            guard let url = view.lastLoadURL else { preconditionFailure("No preview load URL") }
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
                NSURLErrorFailingURLErrorKey: url,
            ])
        }

        func dispose() {
            view.onStop = nil
            coordinator.dispose(webView: view)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class RecordedWebView: WKWebView {
        var loads: [WKNavigation?] = []
        var reloads: [WKNavigation?] = []
        var returnNilFromLoad = false
        var returnNilFromReload = false
        var onStop: (() -> Void)?
        var lastLoadURL: URL?

        init() {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            super.init(frame: .zero, configuration: configuration)
        }

        required init?(coder _: NSCoder) {
            nil
        }

        override func load(_ request: URLRequest) -> WKNavigation? {
            lastLoadURL = request.url
            let navigation = returnNilFromLoad ? nil : super.loadHTMLString(
                "<!doctype html><title>fixture</title>", baseURL: nil
            )
            loads.append(navigation)
            return navigation
        }

        override func reload() -> WKNavigation? {
            let navigation = returnNilFromReload ? nil : super.loadHTMLString(
                "<!doctype html><title>fixture</title>", baseURL: nil
            )
            reloads.append(navigation)
            return navigation
        }

        override func stopLoading() {
            onStop?()
            super.stopLoading()
        }
    }
}
