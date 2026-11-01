import Foundation
import Testing
@testable import Themes

struct ThemeCatalogReloadTests {
    @Test func unchangedReloadDoesNotInvalidateAPreparedChoice() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let next = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        let prepared = try await store.prepareImport(next.encoded())
        let first = try await store.reload()
        let second = try await store.reload()
        #expect(first == second)
        let result = try await store.commitImport(prepared, choice: .replace)
        #expect(result.state.catalog.customThemes == [next])
    }

    @Test func anotherIncompleteGenerationRestartsConfirmationWithoutDroppingKnownGood() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let clock = ThemeCatalogTestClock()
        let store = try ThemeCatalogStore(directoryURL: fixture.root, hooks: .none, now: { clock.read() })
        _ = try await store.reload()
        try Data("{".utf8).write(to: fixture.url(file.stableID))
        _ = try await store.reload()
        clock.advance(.milliseconds(600))
        try Data("{different incomplete generation".utf8).write(to: fixture.url(file.stableID))
        _ = try await store.reload()
        clock.advance(.milliseconds(749))
        #expect(try await store.reload().catalog.customThemes == [file])
        clock.advance(.milliseconds(1))
        #expect(try await store.reload().catalog.customThemes.isEmpty)
    }

    @Test func retainedKnownGoodValuesCountAgainstTheAdmissionCeiling() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        var files: [ThemeFile] = []
        for index in 0 ..< 256 {
            var theme = BundledThemes.light
            theme.name = "Theme \(index)"
            let file = try ThemeFile(theme: theme)
            files.append(file)
            try fixture.put(file)
        }
        let removed = try #require(files.first)
        let clock = ThemeCatalogTestClock()
        let store = try ThemeCatalogStore(directoryURL: fixture.root, hooks: .none, now: { clock.read() })
        _ = try await store.reload()
        try FileManager.default.removeItem(at: fixture.url(removed.stableID))
        let added = try ThemeFile(theme: BundledThemes.dark)
        try fixture.put(added)
        let pending = try await store.reload()
        #expect(pending.catalog.customThemes.count == 256)
        #expect(pending.catalog.customTheme(id: removed.stableID) != nil)
        #expect(pending.catalog.customTheme(id: added.stableID) == nil)
        #expect(pending.needsRecheck)
        clock.advance(.milliseconds(750))
        let confirmed = try await store.reload()
        #expect(confirmed.catalog.customThemes.count == 256)
        #expect(confirmed.catalog.customTheme(id: removed.stableID) == nil)
        #expect(confirmed.catalog.customTheme(id: added.stableID) == added)
        #expect(!confirmed.needsRecheck)
    }

    @Test func corruptPhysicalFilesStillReserveSlotsForNewImports() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        for _ in 0 ..< 256 {
            try Data("{invalid".utf8).write(to: fixture.url(UUID()))
        }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let incoming = try ThemeFile(theme: BundledThemes.light)
        await #expect(throws: ThemeCatalogError.catalogFull) { try await store.prepareImport(incoming.encoded()) }
        #expect(try fixture.names().count == 256)
        let state = await store.currentState()
        #expect(state.catalog.customThemes.isEmpty)
        #expect(state.diagnostics.count == 256)
    }

    @Test func rootReplacementKeepsTheLastPublishedSnapshot() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let baseline = try await store.reload()
        try FileManager.default.moveItem(at: fixture.root, to: fixture.base.appendingPathComponent("moved"))
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        await #expect(throws: ThemeStorageError.directoryChanged) { try await store.reload() }
        #expect(await store.currentState() == baseline)
    }
}
