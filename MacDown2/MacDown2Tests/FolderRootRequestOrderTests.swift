import Foundation
@testable import MacDown2
import Testing
@testable import TextSearch
import Workspace

/// Root choices retire old search authority when dispatched, even before
/// their asynchronous tree/index work begins.
extension WorkspaceIndexFreshnessTests {
    @Test func staleExistingFileFocusCannotSelectInANewerFolder() async throws {
        let oldRoot = try tempRoot(["old.md"])
        let newRoot = try tempRoot(["new.md"])
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }
        let fixture = try makeUnrootedController(index: WorkspaceFileIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        let oldFile = oldRoot.appendingPathComponent("old.md")
        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer {
            controller.beforeRootRebuild = nil
            gate.release()
        }

        let stale = Task {
            await fixture.coordinator.focus(
                controller,
                for: oldFile,
                folder: FolderOpenContext(root: oldRoot, accessURL: nil, selectionURL: oldFile, renameURL: nil),
                encoding: nil
            )
        }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await stale.value
            Issue.record("The old folder rebuild did not start")
            return
        }
        controller.beforeRootRebuild = nil
        controller.model.setFolderRoot(newRoot)
        await controller.setFileTreeRoot(newRoot)
        gate.release()
        await stale.value

        #expect(controller.fileTreeModel.root == newRoot.standardizedFileURL)
        #expect(controller.fileTreeModel.selectedURL == nil)
        #expect(await paths(controller) == ["new.md"])
    }

    @Test func queuedOldFolderChoiceCannotStartAfterANewerDirectRoot() async throws {
        let oldRoot = try tempRoot(["old.md"])
        let newRoot = try tempRoot(["new.md"])
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }
        let probe = IndexWalkProbe()
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        controller.model.setFolderRoot(oldRoot)
        let stale = controller.enqueueFileTreeRoot(oldRoot)
        controller.model.setFolderRoot(newRoot)
        await controller.setFileTreeRoot(newRoot)
        await stale.value

        #expect(controller.fileTreeModel.root == newRoot.standardizedFileURL)
        #expect(controller.folderSearchModel.root == newRoot.standardizedFileURL)
        #expect(await paths(controller) == ["new.md"])
        #expect(probe.count == 1)
    }

    @Test func queuedFolderChoiceRetiresOldSearchBeforeItsTaskStarts() async throws {
        let oldRoot = try tempRoot(["old.md"])
        let newRoot = try tempRoot(["new.md"])
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }
        let fixture = try makeUnrootedController(index: WorkspaceFileIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        controller.model.setFolderRoot(oldRoot)
        await controller.setFileTreeRoot(oldRoot)
        #expect(controller.currentQuickOpenOrigin != nil)

        controller.model.setFolderRoot(newRoot)
        let queued = controller.enqueueFileTreeRoot(newRoot)
        #expect(controller.currentQuickOpenOrigin == nil)
        #expect(controller.folderSearchModel.root == nil)
        await queued.value

        #expect(controller.fileTreeModel.root == newRoot.standardizedFileURL)
        #expect(await paths(controller) == ["new.md"])
    }

    @Test func laterSameFolderChoiceSupersedesAnUnstartedEarlierChoice() async throws {
        let root = try tempRoot(["note.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IndexWalkProbe()
        let fixture = try makeUnrootedController(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller

        controller.model.setFolderRoot(root)
        let older = controller.enqueueFileTreeRoot(root)
        let latest = controller.enqueueFileTreeRoot(root)
        await older.value
        await latest.value

        #expect(controller.fileTreeModel.root == root.standardizedFileURL)
        #expect(await paths(controller) == ["note.md"])
        #expect(probe.count == 1)
    }
}
