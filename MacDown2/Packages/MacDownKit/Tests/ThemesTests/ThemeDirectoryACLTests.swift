import Darwin
import Foundation
import Testing
@testable import Themes

struct ThemeDirectoryACLTests {
    @Test func grantingACLIsNotMadePrivateByMode700() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        try chmod(["+a", "everyone allow list,search,readattr,readextattr,readsecurity", fixture.root.path])
        defer { try? chmod(["-N", fixture.root.path]) }
        var info = stat()
        #expect(lstat(fixture.root.path, &info) == 0)
        #expect(info.st_mode & 0o077 == 0)
        #expect(throws: ThemeStorageError.invalidDirectory) { try ThemeDirectory(url: fixture.root) }
    }

    @Test func laterGrantingACLInvalidatesAnAlreadyPinnedRoot() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let directory = try ThemeDirectory(url: fixture.root)
        try chmod(["+a", "everyone allow list,search", fixture.root.path])
        defer { try? chmod(["-N", fixture.root.path]) }
        #expect(throws: ThemeStorageError.directoryChanged) { try directory.checkRoot() }
    }

    @Test func denyOnlyACLDoesNotGrantAccessToAnotherAccount() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        try chmod(["+a", "everyone deny delete", fixture.root.path])
        defer { try? chmod(["-N", fixture.root.path]) }
        let directory = try ThemeDirectory(url: fixture.root)
        try directory.checkRoot()
    }

    @Test func aLaterAllowEntryIsNotHiddenByAnInitialDenyEntry() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        try chmod(["+a", "everyone deny delete", fixture.root.path])
        defer { try? chmod(["-N", fixture.root.path]) }
        try chmod(["+a", "everyone allow list,search", fixture.root.path])
        #expect(throws: ThemeStorageError.invalidDirectory) { try ThemeDirectory(url: fixture.root) }
    }

    @Test func bootstrapRefusesAGrantingParentWithoutCreatingChildren() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        try chmod(["+a", "everyone allow list,search", fixture.root.path])
        defer { try? chmod(["-N", fixture.root.path]) }
        #expect(throws: ThemeStorageError.invalidDirectory) {
            try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.root, components: ["new", "Themes"])
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("new").path))
    }

    private func chmod(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output; process.standardError = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        if process.terminationStatus != 0 {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
