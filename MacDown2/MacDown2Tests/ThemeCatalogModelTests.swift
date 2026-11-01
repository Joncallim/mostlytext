import Darwin
import Foundation
@testable import MacDown2
import Testing
import Themes

@MainActor
struct ThemeCatalogModelTests {
    @Test func importCopiesBytesIntoManagedStorageAndSelectsTheNewIdentity() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let external = try ThemeFile(theme: BundledThemes.light)
        let source = try fixture.external(external)
        let original = try Data(contentsOf: source)
        let model = try await fixture.start()
        await model.importTheme(from: source)
        #expect(model.customThemes.count == 1)
        let installed = try #require(model.customThemes.first)
        #expect(installed.stableID != external.stableID)
        #expect(model.controller.current.id == installed.theme.id)
        #expect(try Data(contentsOf: source) == original)
        #expect(!model.isBusy)
        await model.shutdown()
    }

    @Test func importConfirmationIsConsumedBeforeDismissalAndCannotRunTwice() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let model = try await fixture.start()
        var changed = original.theme
        changed.name = "Replacement"
        let incoming = try ThemeFile(theme: changed, stableID: original.stableID)
        try await model.importTheme(from: fixture.external(incoming))
        #expect(model.pendingImport != nil)
        #expect(!model.canManage)
        model.resolvePendingImport(.replace)
        #expect(model.pendingImport == nil)
        #expect(model.isBusy)
        model.cancelPendingImport()
        model.resolvePendingImport(.importCopy)
        await model.confirmationTask?.value
        #expect(model.customThemes.count == 1)
        #expect(model.customThemes.first?.displayName == "Replacement")
        #expect(model.problem == nil)
        await model.shutdown()
    }

    @Test func cancelledImportConflictPreservesInstalledAndExternalBytes() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        let managed = try fixture.put(original)
        let model = try await fixture.start()
        var changed = original.theme
        changed.name = "Unaccepted"
        let external = try fixture.external(ThemeFile(theme: changed, stableID: original.stableID))
        let before = try Data(contentsOf: managed)
        let incoming = try Data(contentsOf: external)
        await model.importTheme(from: external)
        model.cancelPendingImport()
        #expect(model.canManage)
        #expect(try Data(contentsOf: managed) == before)
        #expect(try Data(contentsOf: external) == incoming)
        await model.shutdown()
    }

    @Test func deletionConfirmationBindsTheOriginalVersionAndRejectsLaterEdits() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        let managed = try fixture.put(original)
        let model = try await fixture.start()
        await model.prepareDeletion(original.stableID)
        #expect(model.pendingDeletion?.id == original.stableID)
        var changed = original.theme
        changed.name = "Changed after confirmation opened"
        let updated = try ThemeFile(theme: changed, stableID: original.stableID).encoded()
        try updated.write(to: managed)
        model.confirmDeletion()
        model.cancelPendingDeletion()
        await model.confirmationTask?.value
        #expect(model.problem != nil)
        #expect(try Data(contentsOf: managed) == updated)
        await model.shutdown()
    }

    @Test func cancelledDeletionDoesNotTouchBytesOrSelection() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        let managed = try fixture.put(file)
        let model = try await fixture.start()
        model.controller.select(file.theme)
        await model.prepareDeletion(file.stableID)
        model.cancelPendingDeletion()
        model.confirmDeletion()
        #expect(model.canManage)
        #expect(model.controller.current.id == file.theme.id)
        #expect(try Data(contentsOf: managed) == file.encoded())
        await model.shutdown()
    }

    @Test func acceptedDeletionFallsBackAndDuplicateMakesAnIndependentCustomTheme() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let model = try await fixture.start()
        await model.duplicate(BundledThemes.light)
        let file = try #require(model.customThemes.first)
        #expect(file.theme.name != BundledThemes.light.name)
        #expect(model.controller.current.id == file.theme.id)
        await model.prepareDeletion(file.stableID)
        model.confirmDeletion()
        await model.confirmationTask?.value
        #expect(model.customThemes.isEmpty)
        #expect(model.controller.current == BundledThemes.light)
        #expect(!FileManager.default.fileExists(atPath: fixture.managed(file.stableID).path))
        await model.shutdown()
    }

    @Test func shutdownRevokesPendingConfirmationAndCannotRestartAnOldCatalogGeneration() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        let managed = try fixture.put(original)
        let model = try await fixture.start()
        await model.prepareDeletion(original.stableID)
        await model.shutdown()
        #expect(model.pendingDeletion == nil)
        model.confirmDeletion()
        #expect(try Data(contentsOf: managed) == original.encoded())
        model.start()
        #expect(model.status == .stopped)
        #expect(model.store == nil)
        let replacement = try await fixture.start()
        #expect(replacement.status == .ready)
        #expect(replacement.customThemes.count == 1)
        await replacement.shutdown()
    }

    @Test func invalidAndOversizedImportsLeaveTheCatalogUnchanged() async throws {
        let fixture = try ThemeModelFixture(); defer { fixture.cleanup() }
        let model = try await fixture.start()
        let source = fixture.root.appendingPathComponent("incoming.json")
        for bytes in [Data("{invalid}".utf8), Data(repeating: 32, count: ThemeFile.maximumFileBytes + 1)] {
            try bytes.write(to: source)
            await model.importTheme(from: source)
            #expect(model.problem != nil)
            #expect(model.customThemes.isEmpty)
            #expect(!model.isBusy)
            #expect(try Data(contentsOf: source) == bytes)
        }
        await model.shutdown()
    }
}

@MainActor
private struct ThemeModelFixture {
    let root: URL
    let directory: URL
    let suite = "theme-model-test-" + UUID().uuidString

    init() throws {
        guard let physical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        directory = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    func start() async throws -> ThemeCatalogModel {
        let defaults = try #require(UserDefaults(suiteName: suite))
        let controller = ThemeController(preferenceStore: UserDefaultsThemePreferenceStore(defaults: defaults))
        let model = ThemeCatalogModel(controller: controller, location: .existingDirectory(directory))
        model.start()
        await model.startupTask?.value
        await model.refreshTask?.value
        #expect(model.status == .ready)
        return model
    }

    func managed(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    @discardableResult func put(_ file: ThemeFile) throws -> URL {
        let url = managed(file.stableID)
        try file.encoded().write(to: url)
        return url
    }

    func external(_ file: ThemeFile) throws -> URL {
        let url = root.appendingPathComponent("incoming.json")
        try file.encoded().write(to: url)
        return url
    }

    func cleanup() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
