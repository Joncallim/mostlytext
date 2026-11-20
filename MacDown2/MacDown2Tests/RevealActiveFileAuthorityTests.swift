import AppKit
import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
struct RevealActiveFileAuthorityTests {
    @MainActor private struct Fixture {
        let coordinator: WindowCoordinator
        let controller: WindowController
        let window: NSWindow
        let url: URL
        let first: FileDocument
        let request: RevealRequestAuthority

        func cleanUp() {
            coordinator.removeController(controller)
            if !controller.isClosed {
                controller.close()
            }
        }
    }

    private func makeFixture() throws -> Fixture {
        let defaults = try #require(UserDefaults(suiteName: "reveal-authority-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let controller = WindowController(
            model: coordinator.makeWindowModel(), coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: coordinator.fileTreePreferences
        )
        coordinator.controllers = [controller]
        let window = try #require(controller.window)
        let url = URL(fileURLWithPath: "/tmp/reveal-reused-document.md")
        let first = FileDocument(fileURL: url, text: "first")
        controller.model.tabStore.newTab(document: first)
        let request = try #require(RevealRequestAuthority(for: url, controller: controller))
        return Fixture(coordinator: coordinator, controller: controller, window: window,
                       url: url, first: first, request: request)
    }

    @Test func delayedRevealCannotFollowPendingFolderChangeOrFolderABA() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        #expect(fixture.coordinator.revealRequestIsCurrent(
            fixture.request, controller: fixture.controller, window: fixture.window
        ))
        fixture.controller.model.setFolderRoot(URL(fileURLWithPath: "/tmp/reveal-other-root", isDirectory: true))
        #expect(!fixture.coordinator.revealRequestIsCurrent(
            fixture.request, controller: fixture.controller, window: fixture.window
        ), "The workspace root changed before the tree received its async replacement")
        fixture.controller.model.setFolderRoot(nil)
        #expect(!fixture.coordinator.revealRequestIsCurrent(
            fixture.request, controller: fixture.controller, window: fixture.window
        ), "Switching the folder away and back also revokes the delayed request")
    }

    @Test func delayedRevealCannotFollowReusedDocumentIDOrTabABA() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let second = FileDocument(fileURL: fixture.url, text: "second")
        try #require(fixture.first.id == second.id && fixture.first.recoveryEpoch != second.recoveryEpoch)
        fixture.controller.model.tabStore.newTab(document: second)
        #expect(!fixture.coordinator.revealRequestIsCurrent(
            fixture.request, controller: fixture.controller, window: fixture.window
        ), "A new tab and recovery lifetime cannot inherit the old reveal")
        fixture.controller.model.tabStore.activate(fixture.request.identity.tabID)
        #expect(fixture.controller.model.tabStore.activeDocumentIdentity == fixture.request.identity)
        #expect(!fixture.coordinator.revealRequestIsCurrent(
            fixture.request, controller: fixture.controller, window: fixture.window
        ), "Switching away and back cannot revive the old reveal")
    }
}
