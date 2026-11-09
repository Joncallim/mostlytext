import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Preview
import SwiftUI
import Testing
import Themes
import Workspace

/// Folder-search reveals against newer navigation, Find tokens and
/// mounted-editor selection.
@MainActor
@Suite("WindowCoordinator folder-search navigation")
struct FolderSearchNavigationTests {
    private func orderFrontWithoutAnimation(_ window: NSWindow?) {
        window?.animationBehavior = .none
        window?.makeKeyAndOrderFront(nil)
    }

    @Test func existingBackgroundNativeTabIsActivatedAndItsMatchIsRevealed() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "prefix needle suffix".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second document".write(to: secondURL, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        await coordinator.openDocument(at: firstURL, folderRoot: root, folderAccessURL: root)
        let first = try #require(coordinator.controllerForDocument(url: firstURL))
        let firstWindow = try #require(first.window)
        await coordinator.openDocument(
            at: secondURL, folderRoot: root, folderAccessURL: root, relativeTo: firstWindow
        )
        let second = try #require(coordinator.controllerForDocument(url: secondURL))
        let secondWindow = try #require(second.window)
        firstWindow.animationBehavior = .none
        secondWindow.animationBehavior = .none
        let tabGroup = try #require(firstWindow.tabGroup)
        #expect(tabGroup.windows.contains { $0 === secondWindow })
        tabGroup.selectedWindow = secondWindow
        secondWindow.makeKeyAndOrderFront(nil)
        #expect(tabGroup.selectedWindow === secondWindow)

        await coordinator.openFolderSearchResult(
            relativePath: "first.md",
            root: root,
            folderAccessURL: root,
            range: NSRange(location: 7, length: 6)
        )

        #expect(tabGroup.selectedWindow === firstWindow)
        #expect(coordinator.controllers.count == 2, "the existing native tab must be reused")
        let tabID = try #require(first.model.tabStore.tabID(forFileURL: firstURL))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            coordinator.folderSearchEditorLayoutChanged(tabID: tabID.uuidString)
            if first.editorStore.existingSystem(for: tabID.uuidString)?.selectedRange
                == NSRange(location: 7, length: 6) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let system = try #require(first.editorStore.existingSystem(for: tabID.uuidString))
        #expect(system.selectedRange == NSRange(location: 7, length: 6))
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)
    }

    @Test func newerNavigationDuringFileLoadDoesNotPublishFolderSearchResult() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "needle".write(to: root.appendingPathComponent("result.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        var reachedFileLoad = false
        coordinator.afterFolderSearchFileLoad = {
            reachedFileLoad = true
            coordinator.folderSearchNavigationDidChange()
        }

        await coordinator.openFolderSearchResult(
            relativePath: "result.md",
            root: root,
            folderAccessURL: root,
            range: NSRange(location: 0, length: 6)
        )

        #expect(reachedFileLoad)
        #expect(coordinator.controllers.isEmpty)
        #expect(coordinator.pendingFolderSearchReveals.isEmpty)
    }

    @Test func olderFindCompletionTokenCannotInvalidateNewerFolderSearch() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let olderFindToken = coordinator.folderSearchNavigationDidChange()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "prefix needle suffix".write(
            to: root.appendingPathComponent("result.md"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }
        var folderSearchStarted = false
        coordinator.afterFolderSearchFileLoad = {
            folderSearchStarted = true
            #expect(!coordinator.folderSearchNavigationIsCurrent(olderFindToken))
        }
        defer { coordinator.afterFolderSearchFileLoad = nil }

        await coordinator.openFolderSearchResult(
            relativePath: "result.md",
            root: root,
            folderAccessURL: root,
            range: NSRange(location: 7, length: 6)
        )

        #expect(!coordinator.folderSearchNavigationIsCurrent(olderFindToken))
        #expect(folderSearchStarted)
        let controller = try #require(coordinator.controllers.first)
        let activeTabID = try #require(controller.model.tabStore.activeTab?.id.uuidString)
        let system = try #require(controller.editorStore.existingSystem(for: activeTabID))
        #expect(system.selectedRange == NSRange(location: 7, length: 6))
    }

    @Test func newerNavigationSurvivesActualPreviewOnlyToEditorMount() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let preferences = FileTreePreferences()
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "line one\nline two\nline three"))
        let tabID = try #require(model.tabStore.activeTab?.id)
        model.tabStore.setPreviewLayout(.previewOnly, for: tabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        orderFrontWithoutAnimation(controller.window)
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        let findModel = controller.findStore.model(for: tabID.uuidString)
        findModel.query = "line"
        let previewSystem = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        findModel.isActive = true
        findModel.pendingRevealNavigationToken = coordinator.folderSearchNavigationDidChange()
        #expect(findModel.pendingRevealNavigationToken != nil)

        let generation = coordinator.folderSearchRequestGate.begin()
        coordinator.pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
            generation: generation,
            navigationRevision: coordinator.folderSearchNavigationRevision,
            range: NSRange(location: 2, length: 0),
            controllerID: ObjectIdentifier(controller)
        )
        let mounted = AsyncStream<Void>.makeStream()
        coordinator.afterFolderSearchEditorLayoutChange = {
            mounted.continuation.yield(())
        }
        defer {
            coordinator.afterFolderSearchEditorLayoutChange = nil
        }
        let panel = GoToLinePanel(coordinator: coordinator, originController: controller)
        panel.jump(to: "2")
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)

        model.tabStore.setPreviewLayout(.split(fraction: 0.5), for: tabID)
        #expect(await FolderSearchGate.waitForEntry(mounted.stream))

        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        #expect(system === previewSystem)
        #expect(!system.isDetachedFromEditorView)
        #expect(system.selectedRange == NSRange(location: 9, length: 0))
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)
        #expect(findModel.pendingRevealNavigationToken == nil)
    }

    @Test func pendingFolderSearchRevealDrainsIntoTheMountedEditorSelection() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: url)
        }

        await coordinator.openDocument(at: url)
        let controller = try #require(coordinator.controllers.first)
        let tabID = try #require(controller.model.tabStore.tabID(forFileURL: url))
        let generation = coordinator.folderSearchRequestGate.begin()
        coordinator.pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
            generation: generation,
            navigationRevision: coordinator.folderSearchNavigationRevision,
            range: NSRange(location: 2, length: 0),
            controllerID: ObjectIdentifier(controller)
        )
        orderFrontWithoutAnimation(controller.window)

        coordinator.folderSearchEditorLayoutChanged(tabID: tabID.uuidString)

        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        #expect(system.selectedRange == NSRange(location: 2, length: 0))
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)
    }
}

extension FolderSearchNavigationTests {
    @Test func pendingRevealDoesNotUseARowFromAnOlderQuery() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("result.md")
        try "needle after prefix".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        await coordinator.openDocument(at: url, folderRoot: root, folderAccessURL: root)
        let controller = try #require(coordinator.controllerForDocument(url: url))
        await controller.setFileTreeRoot(root)
        controller.folderSearchModel.query = "needle"
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while controller.folderSearchModel.presentedResults.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let row = try #require(controller.folderSearchModel.presentedResults.first)
        let tabID = try #require(controller.model.tabStore.tabID(forFileURL: url))
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        orderFrontWithoutAnimation(controller.window)
        #expect(system.textView.window === controller.window)
        let initialSelection = system.selectedRange
        let generation = coordinator.folderSearchRequestGate.begin()
        coordinator.pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
            generation: generation,
            navigationRevision: coordinator.folderSearchNavigationRevision,
            range: NSRange(location: 8, length: 6),
            controllerID: ObjectIdentifier(controller),
            originControllerID: ObjectIdentifier(controller),
            originGeneration: controller.workspaceRootRequestGeneration,
            originLexicalRoot: root.standardizedFileURL,
            originAccessRoot: controller.folderSearchModel.root,
            originResult: row
        )

        controller.folderSearchModel.query = "other"
        coordinator.folderSearchEditorLayoutChanged(tabID: tabID.uuidString)
        #expect(system.selectedRange == initialSelection)
        #expect(coordinator.pendingFolderSearchReveals[tabID] != nil)
    }
}

extension FolderSearchNavigationTests {
    @Test func selectAllMatchesInvalidatesSuspendedExistingWindowFolderSearch() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("result.md")
        let text = "cat one cat"
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        await coordinator.openDocument(at: url)
        let controller = try #require(coordinator.controllers.first)
        let tab = try #require(controller.model.tabStore.activeTab)
        let identity = tab.id.uuidString
        let system = try #require(controller.editorStore.existingSystem(for: identity))
        orderFrontWithoutAnimation(controller.window)
        #expect(system.textView.window === controller.window)

        let findModel = controller.findStore.model(for: identity)
        findModel.query = "cat"
        findModel.isActive = true
        #expect(await findModel.updateMatches(in: text, preferringLocationNear: 0))
        let selection = try #require(findModel.selectionSetForAllMatches)
        #expect(selection.isMultiple)

        let split = FolderSearchTestSupport.makeSplit(controller: controller, tab: tab, text: text)

        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer { controller.beforeRootRebuild = nil }
        let folderOpen = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "result.md",
                root: root,
                folderAccessURL: root,
                // Deliberately NOT the Select-All primary match (0,3): the multi-selection cache returns the cached set
                // whenever the live ranges equal its primary range, which would hide the collapse this test guards.
                range: NSRange(location: 4, length: 3)
            )
        }
        #expect(await FolderSearchGate.waitForEntry(gate.entered))

        // Exercise the production Select All Matches application path while
        // the older folder-search open is suspended in its root rebuild.
        split.applySelectAllMatches(selection, navigationCoordinator: coordinator)
        split.closeFindBar(findModel)
        #expect(system.selectionSet == selection)

        gate.release()
        await folderOpen.value

        #expect(system.selectionSet == selection)
        #expect(system.selectionSet.isMultiple)
    }
}
