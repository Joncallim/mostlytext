import Darwin
import Foundation
import Testing
@testable import Themes

final class ThemeCatalogTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    func read() -> ContinuousClock.Instant {
        lock.lock(); defer { lock.unlock() }
        return instant
    }

    func advance(_ duration: Duration) {
        lock.lock(); defer { lock.unlock() }
        instant = instant.advanced(by: duration)
    }
}

struct ThemeCatalogStoreTests {
    @Test func importRestartAndNoOpPreserveManagedIdentityWithoutExtraFiles() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let external = try ThemeFile(theme: BundledThemes.light)
        let prepared = try await store.prepareImport(external.encoded())
        let first = try await store.commitImport(prepared, choice: .install)
        #expect(first.changed)
        #expect(first.affectedID != external.stableID)
        #expect(first.state.catalog.customThemes.count == 1)
        let restart = try ThemeCatalogStore(directoryURL: fixture.root)
        let state = try await restart.reload()
        #expect(state.catalog.customThemes.first?.stableID == first.affectedID)
        let again = try await restart.prepareImport(external.encoded())
        let noOp = try await restart.commitImport(again, choice: .useExisting)
        #expect(!noOp.changed)
        #expect(noOp.affectedID == first.affectedID)
        #expect(try fixture.names().count == 1)
    }

    @Test func explicitReplaceAndCopyHaveSeparateStableIdentities() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        let prepared = try await store.prepareImport(replacement.encoded())
        let result = try await store.commitImport(prepared, choice: .replace)
        #expect(result.affectedID == original.stableID)
        #expect(try ThemeFile.decode(fixture.bytes(original.stableID)) == replacement)
        let copyPlan = try await store.prepareImport(replacement.encoded())
        let copy = try await store.commitImport(copyPlan, choice: .importCopy)
        #expect(copy.affectedID != original.stableID)
        #expect(copy.state.catalog.customThemes.count == 2)
    }

    @Test func staleDialogsCannotOverwriteExternalEditsOrOtherImports() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        let plan = try await store.prepareImport(replacement.encoded())
        var externalTheme = BundledThemes.light
        externalTheme.name = "Edited externally"
        let external = try ThemeFile(theme: externalTheme, stableID: original.stableID)
        try fixture.put(external)
        await #expect(throws: ThemeCatalogError.staleImportPlan) { try await store.commitImport(plan, choice: .replace)
        }
        #expect(try fixture.bytes(original.stableID) == external.encoded())
        let first = try await store.prepareImport(replacement.encoded())
        let other = try ThemeFile(theme: BundledThemes.dark)
        let second = try await store.prepareImport(other.encoded())
        _ = try await store.commitImport(second, choice: .install)
        await #expect(throws: ThemeCatalogError.staleImportPlan) {
            try await store.commitImport(first, choice: .replace)
        }
    }

    @Test func rawFormattingChangeAlsoInvalidatesTheBeforeFileBaseline() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        let plan = try await store.prepareImport(replacement.encoded())
        let differentlyFormatted = try original.encoded() + Data("\n".utf8)
        try differentlyFormatted.write(to: fixture.url(original.stableID))
        await #expect(throws: ThemeCatalogError.staleImportPlan) { try await store.commitImport(plan, choice: .replace)
        }
        #expect(try fixture.bytes(original.stableID) == differentlyFormatted)
    }

    @Test func preparedOperationsCannotBeReplayedAgainstAnotherStore() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let first = try ThemeCatalogStore(directoryURL: fixture.root)
        let second = try ThemeCatalogStore(directoryURL: fixture.root)
        let prepared = try await first.prepareImport(file.encoded())
        await #expect(throws: ThemeCatalogError.invalidImportChoice) {
            try await second.commitImport(prepared, choice: .importCopy)
        }
        let deletion = try await first.prepareDeletion(id: file.stableID)
        await #expect(throws: ThemeCatalogError.invalidImportChoice) { try await second.delete(deletion) }
        #expect(try fixture.names().count == 1)
    }

    @Test func explicitDeletionHasAStaleBeforeGuard() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let stale = try await store.prepareDeletion(id: file.stableID)
        let edited = try ThemeFile(theme: BundledThemes.dark, stableID: file.stableID)
        try fixture.put(edited)
        await #expect(throws: ThemeCatalogError.staleImportPlan) { try await store.delete(stale) }
        let fresh = try await store.prepareDeletion(id: file.stableID)
        let result = try await store.delete(fresh)
        #expect(result.changed)
        #expect(result.state.catalog.customThemes.isEmpty)
        #expect(result.state.catalog.available == BundledThemes.all)
        #expect(try fixture.names().isEmpty)
    }

    @Test func corruptionRetainsKnownGoodThenFallsBackWithoutDeletingBytes() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let clock = ThemeCatalogTestClock()
        let store = try ThemeCatalogStore(directoryURL: fixture.root, hooks: .none, now: { clock.read() })
        _ = try await store.reload()
        let broken = Data("{incomplete".utf8)
        try broken.write(to: fixture.url(file.stableID))
        let pending = try await store.reload()
        #expect(pending.catalog.customThemes == [file])
        #expect(pending.needsRecheck)
        #expect(pending.diagnostics.first?.pendingConfirmation == true)
        clock.advance(.milliseconds(749))
        #expect(try await store.reload().catalog.customThemes == [file])
        clock.advance(.milliseconds(1))
        let confirmed = try await store.reload()
        #expect(confirmed.catalog.customThemes.isEmpty)
        #expect(!confirmed.needsRecheck)
        #expect(confirmed.diagnostics.first?.pendingConfirmation == false)
        #expect(try fixture.bytes(file.stableID) == broken)
        try fixture.put(file)
        let repaired = try await store.reload()
        #expect(repaired.catalog.customThemes == [file])
        #expect(repaired.diagnostics.isEmpty)
    }

    @Test func validRepairBeforeConfirmationClearsTheDiagnostic() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let clock = ThemeCatalogTestClock()
        let store = try ThemeCatalogStore(directoryURL: fixture.root, hooks: .none, now: { clock.read() })
        _ = try await store.reload()
        try Data("{".utf8).write(to: fixture.url(file.stableID))
        _ = try await store.reload()
        clock.advance(.milliseconds(100))
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: file.stableID)
        try fixture.put(replacement)
        let state = try await store.reload()
        #expect(state.catalog.customThemes == [replacement])
        #expect(state.diagnostics.isEmpty)
        #expect(!state.needsRecheck)
    }

    @Test func transientDeletionIsConfirmedAndFilenameIdentityMustMatch() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let clock = ThemeCatalogTestClock()
        let store = try ThemeCatalogStore(directoryURL: fixture.root, hooks: .none, now: { clock.read() })
        _ = try await store.reload()
        try FileManager.default.removeItem(at: fixture.url(file.stableID))
        #expect(try await store.reload().catalog.customThemes == [file])
        clock.advance(.milliseconds(750))
        #expect(try await store.reload().catalog.customThemes.isEmpty)
        let wrong = try ThemeFile(theme: BundledThemes.dark)
        try wrong.encoded().write(to: fixture.url(file.stableID))
        let mismatch = try await store.reload()
        #expect(mismatch.catalog.customThemes.isEmpty)
        #expect(mismatch.diagnostics.first?.problem == .invalidTheme)
        #expect(try fixture.bytes(file.stableID) == wrong.encoded())
    }

    @Test func aFreshCorruptCatalogNeverRemovesFilesOrLosesBundledFallbacks() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let id = UUID(); let broken = Data("future or malformed data".utf8)
        try broken.write(to: fixture.url(id))
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let state = try await store.reload()
        #expect(state.catalog.available == BundledThemes.all)
        #expect(state.diagnostics.count == 1)
        #expect(!state.needsRecheck)
        #expect(try fixture.bytes(id) == broken)
    }

    @Test func concurrentAdmissionsCannotCommitAStaleCatalogRevision() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let first = try await store.prepareImport(ThemeFile(theme: BundledThemes.light).encoded())
        let second = try await store.prepareImport(ThemeFile(theme: BundledThemes.dark).encoded())
        let results = await withTaskGroup(of: Bool.self) { group in
            for prepared in [first, second] {
                group.addTask {
                    do {
                        _ = try await store.commitImport(prepared, choice: .install)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        #expect(results.filter(\.self).count == 1)
        #expect(try await store.reload().catalog.customThemes.count == 1)
        #expect(try fixture.names().count == 1)
    }

    @Test func cancellationBeforeAdmissionWritesNothing() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let file = try ThemeFile(theme: BundledThemes.light)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.prepareImport(file.encoded())
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try fixture.names().isEmpty)
    }

    @Test func cancellationAfterPublicationReturnsCommittedStateWithRefreshWarning() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root, hooks: ThemeStorageHooks(flush: { descriptor in
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { return -1 }
            if info.st_mode & S_IFMT == S_IFDIR {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return fsync(descriptor)
        }))
        let file = try ThemeFile(theme: BundledThemes.light)
        let prepared = try await store.prepareImport(file.encoded())
        let result = try await Task { try await store.commitImport(prepared, choice: .install) }.value
        #expect(result.changed)
        #expect(result.warnings.contains(.refreshFailed))
        #expect(result.state.catalog.customThemes.count == 1)
        #expect(try fixture.names().count == 1)
    }
}
