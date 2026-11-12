import Foundation
import LocalResourceAccess
@testable import MacDown2
import Preview
import Testing
import WebKit

/// Fake scheme tasks exercise async ownership and budgets; the app suite runs only on a hosted/test desktop.
@MainActor
struct HTMLPreviewAsyncReadTests {
    @Test func slowOldReadDoesNotBlockOrDeliverIntoNextSavedLoad() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let oldRoot = sandbox.appendingPathComponent("old", isDirectory: true)
        let newRoot = sandbox.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldRoot.appendingPathComponent("slow.txt"))
        try Data("new".utf8).write(to: newRoot.appendingPathComponent("fast.txt"))

        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let admission = PreviewResourceAdmission(readOperation: { reference, directory, cancellation in
            if reference.relativePath == "slow.txt" {
                entered.signal()
                release.wait()
            }
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: cancellation
            )
        })
        let fixture = Fixture(admission: admission)
        let oldURL = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "old", baseURL: oldRoot),
            documentURL: oldRoot.appendingPathComponent("story.html"),
            documentID: "old", recoveryEpoch: UUID(), generation: 1
        ))
        let oldTask = RecordedTask(url: oldURL.appendingPathComponent("slow.txt"))
        fixture.handler.webView(fixture.view, start: oldTask)
        #expect(await Task.detached { Self.waitForSignal(entered) }.value)
        #expect(oldTask.events.isEmpty, "a blocked file read must not block MainActor delivery")

        let newURL = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "new", baseURL: newRoot),
            documentURL: newRoot.appendingPathComponent("story.html"),
            documentID: "new", recoveryEpoch: UUID(), generation: 1
        ))
        let currentTask = RecordedTask(url: newURL.appendingPathComponent("fast.txt"))
        fixture.handler.webView(fixture.view, start: currentTask)
        try await waitForTerminal(currentTask)
        #expect(currentTask.events == ["response", "data", "finish"])
        #expect(currentTask.bytes == Data("new".utf8))

        release.signal()
        try await waitForDrain(admission)
        #expect(oldTask.events.isEmpty, "retired workers have no scheme-task callback authority")
        fixture.handler.retire()
    }

    @Test func stoppedResourceTaskCannotDeliverAfterWorkerReturns() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try Data("resource".utf8).write(to: sandbox.appendingPathComponent("slow.txt"))
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let admission = PreviewResourceAdmission(readOperation: { reference, directory, cancellation in
            entered.signal()
            release.wait()
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: cancellation
            )
        })
        let fixture = Fixture(admission: admission)
        let url = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "saved", baseURL: sandbox),
            documentURL: sandbox.appendingPathComponent("story.html"),
            documentID: "saved", recoveryEpoch: UUID(), generation: 1
        ))
        let task = RecordedTask(url: url.appendingPathComponent("slow.txt"))
        fixture.handler.webView(fixture.view, start: task)
        #expect(await Task.detached { Self.waitForSignal(entered) }.value)
        fixture.handler.webView(fixture.view, stop: task)
        release.signal()
        fixture.handler.retire()
        try await waitForDrain(admission)
        #expect(task.events.isEmpty)
    }

    @Test func activeResourceReadAdmitsSixteenMiBButRejectsOneByteMore() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let limit = PreviewResourceAdmission.resourceLimit
        try Data(repeating: 65, count: limit).write(to: sandbox.appendingPathComponent("allowed.bin"))
        try Data(repeating: 66, count: limit + 1).write(to: sandbox.appendingPathComponent("too-large.bin"))
        let fixture = Fixture(admission: PreviewResourceAdmission())
        let url = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "saved", baseURL: sandbox),
            documentURL: sandbox.appendingPathComponent("story.html"),
            documentID: "saved", recoveryEpoch: UUID(), generation: 1
        ))
        let allowed = RecordedTask(url: url.appendingPathComponent("allowed.bin"))
        fixture.handler.webView(fixture.view, start: allowed)
        try await waitForTerminal(allowed, timeout: .seconds(20))
        #expect(allowed.events == ["response", "data", "finish"])
        #expect(allowed.bytes.count == limit)

        let denied = RecordedTask(url: url.appendingPathComponent("too-large.bin"))
        fixture.handler.webView(fixture.view, start: denied)
        try await waitForTerminal(denied, timeout: .seconds(20))
        #expect(denied.events == ["failure"])
        #expect(denied.bytes.isEmpty)
        fixture.handler.retire()
    }

    @Test func activeHTMLSubresourcesKeepCSPAndRejectExcessHardeningCopies() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try Data("<html><head></head><body>safe</body></html>".utf8)
            .write(to: sandbox.appendingPathComponent("valid.html"))
        try Data([0xFF, 0xFE]).write(to: sandbox.appendingPathComponent("nonutf8.html"))
        let copyDeniedSize = (PreviewHTMLCopyBudget.limit - 16 * 1024 * 1024)
            / MemoryLayout<Character>.stride + 1
        guard copyDeniedSize <= PreviewResourceAdmission.resourceLimit else {
            Issue.record("HTML copy budget cannot be reached beneath the resource cap")
            return
        }
        #expect(PreviewHTMLCopyBudget.hardeningCharge(for: copyDeniedSize) > PreviewHTMLCopyBudget.limit)
        try Data(repeating: 65, count: copyDeniedSize)
            .write(to: sandbox.appendingPathComponent("copy-denied.html"))

        let fixture = Fixture(admission: PreviewResourceAdmission())
        let url = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "saved", baseURL: sandbox),
            documentURL: sandbox.appendingPathComponent("story.html"),
            documentID: "saved", recoveryEpoch: UUID(), generation: 1
        ))
        let valid = RecordedTask(url: url.appendingPathComponent("valid.html"))
        fixture.handler.webView(fixture.view, start: valid)
        try await waitForTerminal(valid)
        #expect(valid.events == ["response", "data", "finish"])
        let validResponse = try #require(valid.response as? HTTPURLResponse)
        #expect(validResponse.value(forHTTPHeaderField: "Content-Type") == HTMLPreviewContentType.mainDocument)
        #expect(validResponse.value(forHTTPHeaderField: "Content-Security-Policy") != nil)
        let validHTML = try #require(String(bytes: valid.bytes, encoding: .utf8))
        #expect(validHTML.contains("<meta http-equiv=\"Content-Security-Policy\""))

        let nonUTF8 = RecordedTask(url: url.appendingPathComponent("nonutf8.html"))
        fixture.handler.webView(fixture.view, start: nonUTF8)
        try await waitForTerminal(nonUTF8)
        #expect(nonUTF8.events == ["response", "data", "finish"])
        #expect(nonUTF8.bytes == Data([0xFF, 0xFE]))
        let rawResponse = try #require(nonUTF8.response as? HTTPURLResponse)
        #expect(rawResponse.value(forHTTPHeaderField: "Content-Type") == "text/html")
        #expect(rawResponse.value(forHTTPHeaderField: "Content-Security-Policy") != nil)

        let overBudget = RecordedTask(url: url.appendingPathComponent("copy-denied.html"))
        fixture.handler.webView(fixture.view, start: overBudget)
        try await waitForTerminal(overBudget, timeout: .seconds(20))
        #expect(overBudget.events == ["failure"])
        #expect(overBudget.bytes.isEmpty)
        fixture.handler.retire()
    }

    @Test func mismatchedSavedDocumentDirectoryCannotGrantResources() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let requestedRoot = sandbox.appendingPathComponent("requested", isDirectory: true)
        let actualRoot = sandbox.appendingPathComponent("actual", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: actualRoot, withIntermediateDirectories: true)
        try Data("unapproved".utf8).write(to: requestedRoot.appendingPathComponent("asset.txt"))
        let fixture = Fixture()
        let url = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "saved", baseURL: requestedRoot),
            documentURL: actualRoot.appendingPathComponent("story.html"),
            documentID: "saved", recoveryEpoch: UUID(), generation: 1
        ))
        let main = RecordedTask(url: url)
        fixture.handler.webView(fixture.view, start: main)
        #expect(main.events == ["response", "data", "finish"])
        let resource = RecordedTask(url: url.appendingPathComponent("asset.txt"))
        fixture.handler.webView(fixture.view, start: resource)
        #expect(resource.events == ["failure"])
    }

    @Test func repeatedSaveAndDisposalRejectEarlierMainDocumentTasks() throws {
        let fixture = Fixture()
        let request = HTMLPreviewRequest(source: "unchanged", baseURL: nil)
        let epoch = UUID()
        let firstURL = try #require(fixture.handler.install(
            request, documentURL: nil, documentID: "same-document", recoveryEpoch: epoch, generation: 1
        ))
        let secondURL = try #require(fixture.handler.install(
            request, documentURL: nil, documentID: "same-document", recoveryEpoch: epoch, generation: 2
        ))
        #expect(firstURL != secondURL)
        let oldTask = RecordedTask(url: firstURL)
        fixture.handler.webView(fixture.view, start: oldTask)
        #expect(oldTask.events == ["failure"])

        fixture.handler.retire()
        let disposedTask = RecordedTask(url: secondURL)
        fixture.handler.webView(fixture.view, start: disposedTask)
        #expect(disposedTask.events == ["failure"])
    }
}

private extension HTMLPreviewAsyncReadTests {
    func makeSandbox() throws -> URL {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(
            "active-html-read-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }

    func waitForDrain(_ admission: PreviewResourceAdmission) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await admission.globalStatus() != .init(reserved: 0, retained: 0) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Active HTML resource reservations did not drain")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        await Task.yield()
    }

    private nonisolated static func waitForSignal(_ signal: DispatchSemaphore) -> Bool {
        signal.wait(timeout: .now() + 5) == .success
    }

    func waitForTerminal(_ task: RecordedTask, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !task.events.contains("finish"), !task.events.contains("failure") {
            guard ContinuousClock.now < deadline else {
                Issue.record("Active HTML resource task did not reach a terminal callback")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    final class Fixture {
        let handler: PreviewSchemeHandler
        let view = makeView()
        let mainURL: URL

        init(admission: PreviewResourceAdmission = .shared) {
            handler = PreviewSchemeHandler(admission: admission)
            guard let url = handler.install(
                HTMLPreviewRequest(source: "<p>delivery-control</p>", baseURL: nil),
                documentURL: nil,
                documentID: "delivery-control", recoveryEpoch: UUID(), generation: 1
            ) else { preconditionFailure("Invalid fixture URL") }
            mainURL = url
        }

        func task(path: String = "") -> RecordedTask {
            let url = path.isEmpty ? mainURL : mainURL.appendingPathComponent(path)
            return RecordedTask(url: url)
        }

        static func makeView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            return WKWebView(frame: .zero, configuration: configuration)
        }
    }

    @MainActor
    final class RecordedTask: NSObject, @MainActor WKURLSchemeTask {
        private let storedRequest: URLRequest
        var request: URLRequest {
            onRequest?()
            return storedRequest
        }

        var events: [String] = []
        var response: URLResponse?
        var bytes = Data()
        var onResponse: (() -> Void)?
        var onData: (() -> Void)?
        var onTerminal: (() -> Void)?
        var onRequest: (() -> Void)?

        init(url: URL) {
            storedRequest = URLRequest(url: url)
        }

        func didReceive(_ response: URLResponse) {
            self.response = response
            events.append("response")
            onResponse?()
        }

        func didReceive(_ data: Data) {
            bytes.append(data)
            events.append("data")
            onData?()
        }

        func didFinish() {
            events.append("finish"); onTerminal?()
        }

        func didFailWithError(_: Error) {
            events.append("failure"); onTerminal?()
        }

        func clearCallbacks() {
            onResponse = nil; onData = nil; onTerminal = nil; onRequest = nil
        }
    }
}
