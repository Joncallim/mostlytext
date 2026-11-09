@testable import FileTree
import Foundation
import Testing

/// EPIC-22 issue #112, Slice 6c. `RecentFolderRoots` (the direct template
/// for `RecentFileDocuments`) has no dedicated test file of its own, so
/// these tests establish the pattern for this whole family of types: real
/// temp files on disk (a security-scoped bookmark needs a real filesystem
/// target to resolve), a fresh named `UserDefaults` suite per test so tests
/// never share persisted state, and `@MainActor` throughout since both
/// `RecentFileDocuments` and `FileTreePreferences` are `@MainActor`.
@MainActor
@Suite("RecentFileDocuments")
struct RecentFileDocumentsTests {
    private final class TempFile {
        let url: URL

        init(name: String = "\(UUID().uuidString).md") throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }

        deinit {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private func makePreferences() throws -> FileTreePreferences {
        let suite = "com.joncallim.macdown2.recent-files-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
    }

    @Test func recordAddsAFileToTheFrontOfTheList() throws {
        let fileA = try TempFile()
        let fileB = try TempFile()
        let store = try RecentFileDocuments(preferences: makePreferences())

        store.record(fileA.url)
        store.record(fileB.url)

        #expect(
            store.documents.map(\.standardizedFileURL) == [fileB.url.standardizedFileURL, fileA.url.standardizedFileURL]
        )
    }

    @Test func recordingAnAlreadyPresentFileMovesItToTheFrontInsteadOfDuplicatingIt() throws {
        let fileA = try TempFile()
        let fileB = try TempFile()
        let store = try RecentFileDocuments(preferences: makePreferences())

        store.record(fileA.url)
        store.record(fileB.url)
        store.record(fileA.url)

        #expect(store.documents.count == 2)
        #expect(store.documents.first?.standardizedFileURL == fileA.url.standardizedFileURL)
    }

    @Test func recordCapsTheListAtTen() throws {
        let store = try RecentFileDocuments(preferences: makePreferences())
        var files: [TempFile] = []
        for _ in 0 ..< 12 {
            let file = try TempFile()
            files.append(file)
            store.record(file.url)
        }

        #expect(store.documents.count == 10)
        // The oldest two recordings were evicted; the most recent ten survive,
        // most-recent-first.
        let expected = files.suffix(10).reversed().map(\.url.standardizedFileURL)
        #expect(store.documents.map(\.standardizedFileURL) == expected)
    }

    @Test func resolveReturnsTheAccessURLForARecordedFile() throws {
        let file = try TempFile()
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(file.url)

        let resolution = store.resolve(file.url)

        #expect(resolution?.lexicalURL.standardizedFileURL == file.url.standardizedFileURL)
        #expect(resolution?.accessURL.standardizedFileURL == file.url.standardizedFileURL)
    }

    @Test func resolveReturnsNilForAFileThatWasNeverRecorded() throws {
        let file = try TempFile()
        let store = try RecentFileDocuments(preferences: makePreferences())

        #expect(store.resolve(file.url) == nil)
    }

    @Test func relativePathsUnderReturnsOnlyDocumentsInsideThatRoot() throws {
        // Issue #112's "Recent-file history feeds Quick Open ranking":
        // `WorkspaceFileIndex.query`'s own `IndexedPath.relativePath` format
        // is `/`-separated with no leading slash, so this must match that
        // exactly for the bonus lookup to ever hit.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let insideNested = root.appendingPathComponent("sub/inside.md")
        let insideTopLevel = root.appendingPathComponent("top.md")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        for url in [insideNested, insideTopLevel, outside] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(insideNested)
        store.record(insideTopLevel)
        store.record(outside)

        #expect(store.relativePaths(under: root) == ["sub/inside.md", "top.md"])
    }

    @Test func clearRemovesEveryEntry() throws {
        let file = try TempFile()
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(file.url)

        store.clear()

        #expect(store.documents.isEmpty)
        #expect(store.resolve(file.url) == nil)
    }

    @Test func pruneMissingFilesDropsEntriesWhoseFileWasDeleted() throws {
        let survivor = try TempFile()
        let doomed = try TempFile()
        let preferences = try makePreferences()
        let store = RecentFileDocuments(preferences: preferences)
        store.record(survivor.url)
        store.record(doomed.url)

        try FileManager.default.removeItem(at: doomed.url)
        store.pruneMissingFiles()

        #expect(store.documents.map(\.standardizedFileURL) == [survivor.url.standardizedFileURL])
    }

    @Test func recordingAnyFilePrunesAlreadyMissingSiblingEntries() throws {
        // `record(_:)` is documented to call `pruneMissingFiles()` itself,
        // so a sibling entry that went stale earlier in the session gets
        // cleaned up on the very next real file open rather than only at
        // the next relaunch.
        let doomed = try TempFile()
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(doomed.url)
        try FileManager.default.removeItem(at: doomed.url)

        let fresh = try TempFile()
        store.record(fresh.url)

        #expect(store.documents.map(\.standardizedFileURL) == [fresh.url.standardizedFileURL])
    }

    @Test func aFreshInstanceReloadsPersistedEntriesFromThePreferencesStore() throws {
        let file = try TempFile()
        let preferences = try makePreferences()
        RecentFileDocuments(preferences: preferences).record(file.url)

        let reloaded = RecentFileDocuments(preferences: preferences)

        #expect(reloaded.documents.map(\.standardizedFileURL) == [file.url.standardizedFileURL])
    }

    @Test func aFreshInstancePrunesAnEntryDeletedSinceItWasLastPersisted() throws {
        let file = try TempFile()
        let preferences = try makePreferences()
        RecentFileDocuments(preferences: preferences).record(file.url)
        try FileManager.default.removeItem(at: file.url)

        let reloaded = RecentFileDocuments(preferences: preferences)

        #expect(reloaded.documents.isEmpty)
    }

    // MARK: - #183 F21: bookmark vs lexical identity

    @Test func resolveFollowsAFileThatMovedAndAdoptsItsNewPath() throws {
        let original = try TempFile(name: "notes.md")
        try Data("original".utf8).write(to: original.url)
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(original.url)
        let oldPath = original.url
        let movedPath = oldPath.deletingLastPathComponent().appendingPathComponent("moved-notes.md")
        try FileManager.default.moveItem(at: oldPath, to: movedPath)

        let resolution = try #require(store.resolve(oldPath))

        #expect(resolution.lexicalURL.lastPathComponent == "moved-notes.md")
        #expect(try String(contentsOf: resolution.lexicalURL, encoding: .utf8) == "original")
    }

    /// Bookmarks resolve path-first, so with an unrelated file at the old path
    /// they resolve to *it*. It must be refused, not opened as the recent file.
    @Test func anUnrelatedFileAtTheOldPathIsNeverOpenedAsTheRecentFile() throws {
        let original = try TempFile(name: "notes.md")
        try Data("original".utf8).write(to: original.url)
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(original.url)
        let oldPath = original.url
        try FileManager.default.moveItem(
            at: oldPath,
            to: oldPath.deletingLastPathComponent().appendingPathComponent("moved-notes.md")
        )
        try Data("unrelated".utf8).write(to: oldPath)

        #expect(store.resolve(oldPath) == nil)
        #expect(store.documents.isEmpty)
    }

    @Test func aWorkingLexicalAliasIsKept() throws {
        let file = try TempFile(name: "keep.md")
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(file.url)

        let resolution = try #require(store.resolve(file.url))

        #expect(resolution.lexicalURL.standardizedFileURL == file.url.standardizedFileURL)
    }

    @Test func pruningKeepsAMovedFileItsBookmarkStillFinds() throws {
        let original = try TempFile(name: "before.md")
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(original.url)
        let movedPath = original.url.deletingLastPathComponent().appendingPathComponent("after.md")
        try FileManager.default.moveItem(at: original.url, to: movedPath)

        store.pruneMissingFiles()

        #expect(store.documents.map(\.lastPathComponent) == ["after.md"])
    }

    @Test func anAtomicSaveReplacingTheFileKeepsItsRecentEntry() throws {
        let file = try TempFile(name: "saved.md")
        let store = try RecentFileDocuments(preferences: makePreferences())
        store.record(file.url)
        let replacement = file.url.deletingLastPathComponent().appendingPathComponent("replacement.tmp")
        try Data("saved".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(file.url, withItemAt: replacement)

        store.noteWrite(of: file.url)

        #expect(store.resolve(file.url) != nil)
        #expect(store.documents.count == 1)
    }

    @Test func aWriteNeverResurrectsAnEntryForAFileThatWasNotRecorded() throws {
        let file = try TempFile(name: "unrecorded.md")
        let store = try RecentFileDocuments(preferences: makePreferences())

        store.noteWrite(of: file.url)

        #expect(store.documents.isEmpty)
    }

    @Test func legacyBookmarkWithoutIdentityRequiresExplicitFileSelection() throws {
        let original = try TempFile(name: "old-recent.md")
        let preferences = try makePreferences()
        let legacy = try original.url.bookmarkData(options: .withSecurityScope)
        preferences.store.recentFileBookmarks = [legacy]

        let store = RecentFileDocuments(preferences: preferences)

        #expect(store.documents.isEmpty)
        #expect(store.unresolvedBookmarkCount == 1)
        #expect(preferences.store.recentFileBookmarks == [legacy])

        try FileManager.default.removeItem(at: original.url)
        try Data("unrelated".utf8).write(to: original.url)
        #expect(store.resolve(original.url) == nil)

        // The user may deliberately select the new object through Open…;
        // that creates a fresh identity and retires this obsolete bookmark.
        store.record(original.url)
        #expect(store.unresolvedBookmarkCount == 0)
        #expect(store.resolve(original.url) != nil)
    }

    @Test func legacyWrappedBookmarkWithoutIdentityRemainsAvailableForReauthorization() throws {
        let original = try TempFile(name: "wrapped-recent.md")
        let preferences = try makePreferences()
        let bookmark = try original.url.bookmarkData(options: .withSecurityScope)
        struct LegacyRecord: Encodable {
            let bookmark: Data
            let lexicalURL: URL
        }
        let legacy = try JSONEncoder().encode(LegacyRecord(bookmark: bookmark, lexicalURL: original.url))
        preferences.store.recentFileBookmarks = [legacy]

        let store = RecentFileDocuments(preferences: preferences)

        #expect(store.documents.isEmpty)
        #expect(store.unresolvedBookmarkCount == 1)
        #expect(preferences.store.recentFileBookmarks == [legacy])
    }
}
