import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

@MainActor
struct WatcherBaselineOrderingTests {
    private final class FirstCallGate {
        private var entered = false
        private var enteredWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func pauseFirstCall() async {
            guard !entered else { return }
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }

        func waitUntilEntered() async {
            if entered {
                return
            }
            await withCheckedContinuation { enteredWaiter = $0 }
        }

        func release() {
            releaseWaiter?.resume()
            releaseWaiter = nil
        }
    }

    private final class ObservationGate {
        private var seen = false
        private var waiter: CheckedContinuation<Void, Never>?

        func record() {
            seen = true
            waiter?.resume()
            waiter = nil
        }

        func waitForFirst() async {
            if seen {
                return
            }
            await withCheckedContinuation { waiter = $0 }
        }
    }

    private struct Fixture {
        let directory: URL
        let url: URL
        let model: WorkspaceModel
        let controller: ExternalFileController
    }

    private func makeFixture(encoding: FileEncodingMetadata) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("cafe.txt")
        try "caf\u{E9}".write(to: url, atomically: false, encoding: .utf8)
        let document = FileDocument(fileURL: url, text: "caf\u{E9}", encoding: encoding)
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        )
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(
            model: model, editorStore: EditorTextSystemStore(), identity: "baseline-ordering-test"
        )
        return Fixture(directory: directory, url: url, model: model, controller: controller)
    }

    private func replaceActiveDocument(
        _ model: WorkspaceModel, url: URL, encoding: FileEncodingMetadata
    ) -> FileDocument {
        let replacement = FileDocument(fileURL: url, text: "caf\u{E9}", encoding: encoding)
        model.tabStore.updateActiveDocument { _ in replacement }
        return replacement
    }

    private func expectUTF8Snapshot(_ controller: ExternalFileController) async {
        switch await controller.monitor.snapshotNow() {
        case let .available(snapshot), let .moved(snapshot):
            #expect(snapshot.text == "caf\u{E9}")
            #expect(snapshot.encoding == .utf8)
        case let .missing(url):
            Issue.record("the monitored file disappeared: \(url)")
        case let .unavailable(url, issue):
            Issue.record("the monitored file became unavailable at \(url): \(issue)")
        }
    }

    @Test func anOlderSameFileUpdateCannotRestoreItsEncodingAfterANewerUpdate() async throws {
        let utf8 = FileEncodingMetadata.utf8Default
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let fixture = try makeFixture(encoding: utf8)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller
        let observations = ObservationGate()
        controller.afterObservationContextHandled = { _ in observations.record() }
        controller.synchronize(with: fixture.model.activeDocument)
        await controller.bindTask?.value
        await observations.waitForFirst()

        let gate = FirstCallGate()
        controller.beforeBaselineUpdate = { await gate.pauseFirstCall() }
        let older = replaceActiveDocument(fixture.model, url: fixture.url, encoding: latin1)
        controller.synchronize(with: older)
        let olderUpdate = try #require(controller.baselineUpdateTask)
        await gate.waitUntilEntered()

        let newer = replaceActiveDocument(fixture.model, url: fixture.url, encoding: utf8)
        controller.synchronize(with: newer)
        await controller.baselineUpdateTask?.value
        gate.release()
        await olderUpdate.value
        await expectUTF8Snapshot(controller)
        controller.dispose()
        await controller.bindTask?.value
    }

    @Test func aQueuedFirstBindUsesThePolicyCurrentWhenItActuallyBinds() async throws {
        let utf8 = FileEncodingMetadata.utf8Default
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let fixture = try makeFixture(encoding: latin1)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller
        let gate = FirstCallGate()
        controller.beforeInitialMonitorBind = { await gate.pauseFirstCall() }
        controller.synchronize(with: fixture.model.activeDocument)
        let queuedBind = try #require(controller.bindTask)
        await gate.waitUntilEntered()

        let newer = replaceActiveDocument(fixture.model, url: fixture.url, encoding: utf8)
        controller.synchronize(with: newer)
        await controller.baselineUpdateTask?.value
        gate.release()
        await queuedBind.value
        await expectUTF8Snapshot(controller)
        controller.dispose()
        await controller.bindTask?.value
    }
}
