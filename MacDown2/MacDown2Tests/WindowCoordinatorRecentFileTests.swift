import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// `WindowCoordinator.openRecentFile(_:)` (EPIC-22 issue #112, Slice 6c). An
/// independent hostile review of this slice found a real bug here: the
/// method opened `resolution.accessURL` (the security-scoped bookmark's
/// physical, symlink-*resolved* target) instead of `resolution.lexicalURL`
/// (the user-facing path actually recorded/clicked) — unlike its own doc
/// comment's claim to mirror `openRecentFolder(_:)`, which deliberately
/// opens the lexical alias and keeps `accessURL` separate. For an ordinary
/// file the two URLs are identical, so this only surfaces when some
/// COMPONENT of the recorded path is a symlink — a symlinked PARENT
/// DIRECTORY (e.g. an aliased folder on the user's Desktop), not the file
/// itself: `FileStore.readSnapshot`'s own `metadata(at:)` uses
/// `FileManager.attributesOfItem(atPath:)`, which does not traverse a
/// symlink at the FINAL path component, so a file that is *itself* a
/// symlink can never successfully open at all (`.notRegularFile`) — this is
/// a separate, pre-existing `FileStore` limitation, unrelated to this fix,
/// so this test does not exercise that case.
@MainActor
@Suite("WindowCoordinator recent files")
struct WindowCoordinatorRecentFileTests {
    private static func makeCoordinatorAndController() -> (WindowCoordinator, WindowController) {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let controller = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return (coordinator, controller)
    }

    @Test func openingARecentFileThroughASymlinkedParentDirectoryOpensTheLexicalPath() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let realDirectory = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        let realFile = realDirectory.appendingPathComponent("note.md")
        try Data().write(to: realFile)

        let aliasDirectory = base.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasDirectory, withDestinationURL: realDirectory)
        let lexicalFile = aliasDirectory.appendingPathComponent("note.md")

        let (coordinator, _) = Self.makeCoordinatorAndController()
        defer { coordinator.controllers.forEach { $0.close() } }
        // Records against the lexical (through-the-symlinked-directory)
        // path, exactly like a real `openDocument(at: lexicalFile)` would
        // (`RecentFileDocuments.record(_:)` keys on whatever URL is passed
        // in). `resolve(_:)` bookmarks/resolves against the PHYSICAL target
        // (`resolvingSymlinksInPath()`), so `resolution.accessURL` here is
        // `realFile`, genuinely different from `resolution.lexicalURL`.
        coordinator.recentFileDocuments.record(lexicalFile)
        let resolution = try #require(coordinator.recentFileDocuments.resolve(lexicalFile))
        #expect(resolution.lexicalURL.standardizedFileURL == lexicalFile.standardizedFileURL)
        #expect(resolution.accessURL.standardizedFileURL == realFile.standardizedFileURL)

        let controllersBefore = coordinator.controllers.count
        let opening = try #require(coordinator.openRecentFile(lexicalFile))
        await opening.value
        #expect(coordinator.controllers.count == controllersBefore + 1)

        let opened = try #require(coordinator.controllers.last)
        #expect(
            opened.model.activeDocument?.fileURL?.standardizedFileURL == lexicalFile.standardizedFileURL,
            "must reopen the lexical path, not silently resolve to its real target"
        )
    }

    @Test func openingAnOrdinaryRecentFileOpensItAndRePromotesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileA = root.appendingPathComponent("a.md")
        let fileB = root.appendingPathComponent("b.md")
        try Data().write(to: fileA)
        try Data().write(to: fileB)

        let (coordinator, _) = Self.makeCoordinatorAndController()
        defer { coordinator.controllers.forEach { $0.close() } }
        coordinator.recentFileDocuments.record(fileA)
        coordinator.recentFileDocuments.record(fileB)
        #expect(coordinator.recentFileDocuments.documents.first?.standardizedFileURL == fileB.standardizedFileURL)

        let controllersBefore = coordinator.controllers.count
        let opening = try #require(coordinator.openRecentFile(fileA))
        await opening.value
        #expect(coordinator.controllers.count == controllersBefore + 1)

        let opened = try #require(coordinator.controllers.last)
        #expect(opened.model.activeDocument?.fileURL?.standardizedFileURL == fileA.standardizedFileURL)
        // Reopening re-promotes it to the front, the same MRU behavior
        // `openRecentFolder`/`openFolder` already give recent folders.
        #expect(coordinator.recentFileDocuments.documents.first?.standardizedFileURL == fileA.standardizedFileURL)
    }
}
