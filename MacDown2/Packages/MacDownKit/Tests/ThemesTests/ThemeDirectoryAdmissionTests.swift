import Darwin
import Foundation
import Testing
@testable import Themes

struct ThemeDirectoryAdmissionTests {
    @Test func requiresPrivateNonSymlinkRootAndAncestors() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.root.path)
        #expect(throws: ThemeStorageError.invalidDirectory) { try fixture.directory() }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.root.path)
        let alias = fixture.base.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
        #expect(throws: ThemeStorageError.invalidDirectory) { try ThemeDirectory(url: alias) }
        let child = fixture.root.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        #expect(throws: ThemeStorageError.invalidDirectory) {
            try ThemeDirectory(url: alias.appendingPathComponent("child"))
        }
    }

    @Test func observedVolumeOwnershipIsEnforced() throws {
        let requested = ProcessInfo.processInfo.environment["MOSTLYTEXT_TEST_THEME_VOLUME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let fixture = try ThemeDirectoryFixture(baseDirectory: requested)
        defer { fixture.cleanup() }
        var volume = statfs()
        #expect(statfs(fixture.root.path, &volume) == 0)
        let ignoresOwnership = volume.f_flags & UInt32(MNT_IGNORE_OWNERSHIP) != 0
        print("Theme storage volume: ownershipIgnored=\(ignoresOwnership)")
        if ignoresOwnership {
            #expect(throws: ThemeStorageError.invalidDirectory) { try fixture.directory() }
        } else {
            _ = try fixture.directory()
        }
    }

    @Test func refusesLinksNonregularFilesAndOversizedBytes() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try fixture.directory()
        let outside = fixture.base.appendingPathComponent("outside")
        try Data("untouched outside".utf8).write(to: outside)
        let id = UUID(); let url = fixture.url(id); let name = ThemeDirectory.name(for: id)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        #expect(throws: ThemeStorageError.self) { try directory.read(name) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.linkItem(at: outside, to: url)
        #expect(throws: ThemeStorageError.unsafeFile) { try directory.read(name) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: ThemeStorageError.unsafeFile) { try directory.read(name) }
        try FileManager.default.removeItem(at: url)
        #expect(mkfifo(url.path, 0o600) == 0)
        #expect(throws: ThemeStorageError.unsafeFile) { try directory.read(name) }
        try FileManager.default.removeItem(at: url)
        try Data(repeating: 0x20, count: ThemeFile.maximumFileBytes + 1).write(to: url)
        #expect(throws: ThemeStorageError.fileTooLarge) { try directory.read(name) }
        #expect(try Data(contentsOf: outside) == Data("untouched outside".utf8))
    }

    @Test func boundedReadDetectsAnInPlaceChange() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let id = UUID(); let url = fixture.url(id)
        try Data(repeating: 0x61, count: 8192).write(to: url)
        let directory = try fixture.directory(hooks: ThemeStorageHooks(afterReadChunk: { count in
            if count == 4096 {
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.write(contentsOf: Data([0x62]))
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)],
                                                      ofItemAtPath: url.path)
            }
        }))
        #expect(throws: ThemeStorageError.changedDuringRead) { try directory.read(ThemeDirectory.name(for: id)) }
    }

    @Test func scannerBoundsAllEntriesAndManagedFiles() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try fixture.directory()
        for index in 0 ..< 1025 {
            try Data().write(to: fixture.root.appendingPathComponent("unrecognized-\(index)"))
        }
        #expect(throws: ThemeStorageError.tooManyDirectoryEntries) { try directory.identifiers() }
        for name in try fixture
            .names() {
            try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(name))
        }
        for _ in 0 ..< 257 {
            try Data().write(to: fixture.url(UUID()))
        }
        #expect(throws: ThemeCatalogError.catalogFull) { try directory.identifiers() }
    }
}
