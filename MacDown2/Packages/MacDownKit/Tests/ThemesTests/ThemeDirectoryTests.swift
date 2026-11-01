import Darwin
import Foundation
import Testing
@testable import Themes

struct ThemeDirectoryFixture: Sendable {
    let base: URL
    let root: URL

    init(baseDirectory: URL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)) throws {
        guard let physicalPath = realpath(baseDirectory.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // Foundation normalizes /private/tmp back to the /tmp symlink on this
        // host. Use the kernel's physical path for no-follow fixture admission.
        let physical = URL(fileURLWithPath: String(cString: physicalPath), isDirectory: true)
        free(physicalPath)
        base = physical.appendingPathComponent("mostlytext-theme-store-" + UUID().uuidString, isDirectory: true)
        root = base.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: base)
    }

    func directory(hooks: ThemeStorageHooks = .none) throws -> ThemeDirectory {
        try ThemeDirectory(url: root, hooks: hooks)
    }

    func url(_ id: UUID) -> URL {
        root.appendingPathComponent(ThemeDirectory.name(for: id))
    }

    func put(_ file: ThemeFile) throws {
        try file.encoded().write(to: url(file.stableID))
    }

    func bytes(_ id: UUID) throws -> Data {
        try Data(contentsOf: url(id))
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
    }
}

struct ThemeDirectoryTests {
    @Test func installIsExclusiveAndPublishesValidatedBytesWithPrivateMode() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try fixture.directory()
        let file = try ThemeFile(theme: BundledThemes.light)
        let result = try directory.install(file)
        #expect(result.rootStillCurrent)
        #expect(result.preservedStagingName == nil)
        #expect(try fixture.bytes(file.stableID) == file.encoded())
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.url(file.stableID).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try directory.identifiers() == [file.stableID])
        #expect(throws: ThemeStorageError.self) { try directory.install(file) }
        #expect(try fixture.names() == [ThemeDirectory.name(for: file.stableID)])
    }

    @Test func replaceRetainsIdentityAndDeletesOnlyTheAcceptedBaselineStage() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try fixture.directory()
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let before = try directory.read(ThemeDirectory.name(for: original.stableID))
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        let result = try directory.replace(replacement, expected: before.fingerprint)
        #expect(result.preservedStagingName == nil)
        #expect(try ThemeFile.decode(fixture.bytes(original.stableID)) == replacement)
        #expect(try fixture.names().count == 1)
    }

    @Test func staleBaselineIsRefusedBeforeExchange() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try fixture.directory()
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let baseline = try directory.read(ThemeDirectory.name(for: original.stableID)).fingerprint
        let competing = Data("external writer".utf8)
        try competing.write(to: fixture.url(original.stableID), options: .atomic)
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        #expect(throws: ThemeStorageError.staleFile) { try directory.replace(replacement, expected: baseline) }
        #expect(try fixture.bytes(original.stableID) == competing)
        #expect(try fixture.names().count == 1)
    }

    @Test func writerBetweenBaselineAndExchangeIsRestored() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let competing = Data("wins just before exchange".utf8)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(beforeExchange: {
            try competing.write(to: fixture.url(original.stableID), options: .atomic)
        }))
        let baseline = try directory.read(ThemeDirectory.name(for: original.stableID)).fingerprint
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        #expect(throws: ThemeStorageError.staleFile) { try directory.replace(replacement, expected: baseline) }
        #expect(try fixture.bytes(original.stableID) == competing)
        #expect(try fixture.names().count == 1)
    }

    @Test func newerPostExchangeWriterKeepsTheDestinationAndDisplacedVersionIsPreserved() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let newest = Data("newest writer".utf8)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(afterExchange: {
            try newest.write(to: fixture.url(original.stableID), options: .atomic)
            throw ThemeStorageError.staleFile
        }))
        let baseline = try directory.read(ThemeDirectory.name(for: original.stableID)).fingerprint
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        do {
            _ = try directory.replace(replacement, expected: baseline)
            Issue.record("Expected preserved recovery")
        } catch let ThemeStorageError.recoveryRequired(name) {
            #expect(try Data(contentsOf: fixture.root.appendingPathComponent(name)) == original.encoded())
        }
        #expect(try fixture.bytes(original.stableID) == newest)
        #expect(try fixture.names().count == 2)
    }

    @Test func writerDuringRollbackIsPreservedInsteadOfDeletedAsOurStage() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let original = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(original)
        let newest = Data("wins in the rollback interval".utf8)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(
            afterExchange: { throw ThemeStorageError.staleFile },
            beforeRollback: { try newest.write(to: fixture.url(original.stableID), options: .atomic) }
        ))
        let baseline = try directory.read(ThemeDirectory.name(for: original.stableID)).fingerprint
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: original.stableID)
        do {
            _ = try directory.replace(replacement, expected: baseline)
            Issue.record("Expected preserved rollback winner")
        } catch let ThemeStorageError.recoveryRequired(name) {
            #expect(try Data(contentsOf: fixture.root.appendingPathComponent(name)) == newest)
        }
        #expect(try fixture.bytes(original.stableID) == original.encoded())
    }

    @Test func exclusiveInstallDoesNotOverwriteACompetingFile() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        let competing = Data("new file at the chosen UUID".utf8)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(beforeExchange: {
            try competing.write(to: fixture.url(file.stableID), options: .atomic)
        }))
        #expect(throws: ThemeStorageError.self) { try directory.install(file) }
        #expect(try fixture.bytes(file.stableID) == competing)
        #expect(try fixture.names().count == 1)
    }

    @Test func deleteVerifiesTheMovedObjectAndRestoresACompetingEdit() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let competing = Data("changed before delete".utf8)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(beforeExchange: {
            try competing.write(to: fixture.url(file.stableID), options: .atomic)
        }))
        let baseline = try directory.read(ThemeDirectory.name(for: file.stableID)).fingerprint
        #expect(throws: ThemeStorageError.staleFile) { try directory.delete(id: file.stableID, expected: baseline) }
        #expect(try fixture.bytes(file.stableID) == competing)
        #expect(try fixture.names().count == 1)
        let ordinary = try fixture.directory()
        let current = try ordinary.read(ThemeDirectory.name(for: file.stableID)).fingerprint
        _ = try ordinary.delete(id: file.stableID, expected: current)
        #expect(try fixture.names().isEmpty)
    }

    @Test func rootReplacementBeforePublicationCannotRedirectTheWrite() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let moved = fixture.base.appendingPathComponent("moved")
        let directory = try fixture.directory(hooks: ThemeStorageHooks(beforeExchange: {
            try FileManager.default.moveItem(at: fixture.root, to: moved)
            try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }))
        let file = try ThemeFile(theme: BundledThemes.light)
        #expect(throws: ThemeStorageError.directoryChanged) { try directory.install(file) }
        #expect(try fixture.names().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test func failedFileFlushLeavesTheOldThemeAndNoStage() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let file = try ThemeFile(theme: BundledThemes.light)
        try fixture.put(file)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(flush: { _ in errno = EIO; return -1 }))
        let baseline = try directory.read(ThemeDirectory.name(for: file.stableID)).fingerprint
        let replacement = try ThemeFile(theme: BundledThemes.dark, stableID: file.stableID)
        #expect(throws: ThemeStorageError.unavailable(EIO)) { try directory.replace(replacement, expected: baseline) }
        #expect(try fixture.bytes(file.stableID) == file.encoded())
        #expect(try fixture.names().count == 1)
    }

    @Test func directoryFlushFailureAfterPublicationIsAWarning() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try fixture.directory(hooks: ThemeStorageHooks(flush: { descriptor in
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { return -1 }
            if info.st_mode & S_IFMT == S_IFDIR {
                errno = EIO; return -1
            }
            return fsync(descriptor)
        }))
        let file = try ThemeFile(theme: BundledThemes.light)
        let result = try directory.install(file)
        #expect(result.durabilityWarning)
        #expect(try fixture.bytes(file.stableID) == file.encoded())
    }
}
