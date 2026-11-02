@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceModelFileOperations")
struct WorkspaceModelFileTests {
    // MARK: - Open file

    @Test func openFileLoadsDocument() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("# Hello", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()

        #expect(model.activeDocument?.text == "# Hello")
        #expect(model.activeDocument?.format.id == "markdown")
        #expect(model.activeDocument?.state == .clean)
    }

    @Test func openFileCancelledLeavesWorkspaceEmpty() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        #expect(model.activeDocument == nil)
    }

    @Test func openFileWhileDirtyOpensNewTabWithoutPrompt() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let firstURL = directory.appendingPathComponent("first.md")
        let secondURL = directory.appendingPathComponent("second.md")
        _ = try? FileStore().write("first", to: firstURL)
        _ = try? FileStore().write("second", to: secondURL)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = firstURL

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("edited") }

        panel.nextFileURL = secondURL
        await model.openFile()

        #expect(model.tabStore.pendingCloseTabID == nil)
        #expect(model.tabStore.tabs.count == 2)
        #expect(model.activeDocument?.text == "second")
    }

    @Test func openSameFileTwiceActivatesExistingTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("content", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.newDocument()
        panel.nextFileURL = url
        await model.openFile()

        #expect(model.tabStore.tabs.count == 2)
        #expect(model.activeDocument?.fileURL == url)
    }

    // MARK: - Save / Save As

    @Test func saveExistingFileWritesToDisk() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("old", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("new") }

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "new")
    }

    @Test func saveUntitledUsesSavePanel() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("saved.md")

        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("content") }

        await model.save()

        #expect(model.activeDocument?.fileURL == url)
        #expect(model.activeDocument?.state == .clean)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "content")
    }

    @Test func saveCancelledKeepsDocumentOpenAndDirty() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("content") }

        await model.save()

        #expect(model.activeDocument?.fileURL == nil)
        #expect(model.activeDocument?.state == .dirty)
    }

    @Test func saveWithoutDocumentSetsError() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        await model.save()

        if case .noActiveDocument = model.lastError {
            // pass
        } else {
            Issue.record("Expected .noActiveDocument, got \(String(describing: model.lastError))")
        }
    }

    @Test func saveToReadOnlyDirectoryFails() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("content", to: url)

        var attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        attributes?[FileAttributeKey.posixPermissions] = 0o555
        try? FileManager.default.setAttributes(attributes ?? [:], ofItemAtPath: directory.path)
        defer {
            var reset = try? FileManager.default.attributesOfItem(atPath: directory.path)
            reset?[FileAttributeKey.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(reset ?? [:], ofItemAtPath: directory.path)
        }

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("edited") }

        await model.save()

        #expect(model.activeDocument?.state == .dirty)
        if case .saveFailed = model.lastError {
            // pass
        } else {
            Issue.record("Expected .saveFailed, got \(String(describing: model.lastError))")
        }
    }

    @Test func ordinarySaveRefusesToOverwriteAnExternalConflict() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("conflict.md")
        let store = FileStore()
        _ = try store.write("baseline", to: url)
        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("local") }
        _ = try store.write("disk", to: url)
        let snapshot = try store.readSnapshot(from: url)
        model.tabStore.updateActiveDocument {
            $0.reconcilingExternalSnapshot(snapshot).document
        }

        await model.save()

        #expect(model.activeDocument?.state == .conflict)
        #expect(try store.read(from: url).content == "disk")
        if case .unresolvedExternalConflict = model.lastError {
            // expected
        } else {
            Issue.record("Expected unresolved external conflict, got \(String(describing: model.lastError))")
        }
    }

    @Test func ordinarySaveDetectsExternalWriteDuringMonitorDebounce() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("debounced-conflict.md")
        _ = try FileStore().write("baseline", to: url)
        let store = FileStore(afterBaselineVerification: { url in
            try Data("external during debounce".utf8).write(to: url, options: .atomic)
        })
        let document = try FileDocument(fileURL: url, fileStore: store)
            .load()
            .edited(text: "local edit")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        await model.save()

        #expect(model.activeDocument?.text == "local edit")
        #expect(model.activeDocument?.state == .conflict)
        #expect(try FileStore().read(from: url).content == "external during debounce")
        if case .unresolvedExternalConflict = model.lastError {
            // expected
        } else {
            Issue.record("Expected unresolved external conflict")
        }
    }

    @Test func saveAdoptsAnExternallyReconciledBaselineAfterAnEarlierSave() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("reconciled.md")
        let store = FileStore()
        _ = try store.write("baseline", to: url)
        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("first local") }
        await model.save()
        #expect(model.activeDocument?.state == .clean)

        _ = try store.write("external baseline", to: url)
        let external = try store.readSnapshot(from: url)
        model.tabStore.updateActiveDocument { $0.reconcilingExternalSnapshot(external).document }
        model.tabStore.updateActiveDocument { $0.updatingText("second local") }
        #expect(model.activeDocument?.lastKnownRevision == external.revision)
        #expect(try model.activeDocument?.fileStore.readSnapshot(from: url).revision == external.revision)

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(try store.read(from: url).content == "second local")
    }

    @Test func saveMergesAcceptedBaselineIntoALaterLocalEdit() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("mid-save-edit.md")
        _ = try FileStore().write("baseline", to: url)
        let barrier = SavePublicationBarrier()
        let delayedStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let document = try FileDocument(fileURL: url, fileStore: delayedStore)
            .load()
            .edited(text: "first local")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        let save = Task { @MainActor in await model.save() }
        // `onTimeout` MUST unblock the barrier's own stored continuation
        // (`cancelWaiters()`), not just record the issue: `waitForFirstPublication()`
        // is a bare `withCheckedContinuation` with no cancellation handler, and
        // `withTaskGroup` always awaits every child task (cancelled or not)
        // before returning -- an un-resumed continuation hangs `waitForSignal`,
        // and therefore this whole test, forever rather than failing. An
        // independent review of this exact fix caught this (this call site
        // and WorkspaceModelFileSaveAsTests.swift's own twin originally
        // omitted it) with an empirical repro showing the hang.
        await waitForSignal(
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: {
                barrier.cancelWaiters()
                Issue.record("Timed out waiting for delayed save publication")
            }
        )
        model.tabStore.updateActiveDocument { $0.edited(text: "second local") }
        barrier.allowPublication()
        await save.value

        #expect(model.activeDocument?.text == "second local")
        #expect(model.activeDocument?.state == .dirty)
        #expect(model.activeDocument?.lastKnownRevision?.sha256 != document.lastKnownRevision?.sha256)
        #expect(try FileStore().read(from: url).content == "first local")

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(try FileStore().read(from: url).content == "second local")
    }
}
