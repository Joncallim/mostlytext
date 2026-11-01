import CommandBridge
import Darwin
import Foundation
import Testing

struct CommandEndpointTests {
    private final class Fixture {
        let root: URL

        init() throws {
            var template = Array("/private/tmp/mtc-XXXXXX".utf8CString)
            let path = try template.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress, let pointer = mkdtemp(base) else {
                    throw CommandEndpointError.unavailable(errno)
                }
                return String(cString: pointer)
            }
            root = URL(fileURLWithPath: path, isDirectory: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func location(_ identity: String = "app.mostlytext.test") throws -> CommandEndpointLocation {
            try CommandEndpointLocation(runtimeDirectory: root, productIdentity: identity)
        }

        func prepareDirectory() throws -> CommandEndpointLocation {
            let location = try location()
            try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            return location
        }
    }

    @Test func identityProducesStableShortDistinctPaths() throws {
        let fixture = try Fixture()
        let first = try fixture.location()
        #expect(try first == fixture.location())
        #expect(try first.socketPath != fixture.location("another.product").socketPath)
        #expect(first.socketPath.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path))
        #expect(try fixture.location("é").socketPath != fixture.location("e\u{301}").socketPath)
        #expect(!FileManager.default.fileExists(atPath: first.directory.path))
    }

    @Test func invalidAndOverlongLocationsCreateNothing() throws {
        let fixture = try Fixture()
        for identity in ["", "has\0nul", String(repeating: "a", count: 1025)] {
            #expect(throws: CommandEndpointError.invalidLocation) { try fixture.location(identity) }
        }
        #expect(throws: CommandEndpointError.invalidLocation) {
            try CommandEndpointLocation(runtimeDirectory: #require(URL(string: "https://example.test/runtime")),
                                        productIdentity: "app")
        }
        #expect(throws: CommandEndpointError.invalidLocation) {
            try CommandEndpointLocation(
                runtimeDirectory: fixture.root.appendingPathComponent(String(repeating: "a", count: 104)),
                productIdentity: "app"
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test func osRuntimeLocationDoesNotCreateAnEndpoint() throws {
        let location = try CommandEndpointLocation.forCurrentUser(productIdentity: UUID().uuidString)
        let physical = try #require(realpath(location.runtimeDirectory.path, nil))
        defer { free(physical) }
        #expect(location.runtimeDirectory.path == String(cString: physical))
        #expect(!FileManager.default.fileExists(atPath: location.directory.path))
    }

    @Test func runtimeParentSymlinkIsRefused() throws {
        let fixture = try Fixture()
        let alias = fixture.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
        let location = try CommandEndpointLocation(runtimeDirectory: alias, productIdentity: "app")
        #expect(throws: CommandEndpointError.self) { try CommandEndpointLease(location: location) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == fixture.root.path)
    }

    @Test func exclusiveLeaseSurvivesContenderAndCanBeReacquired() throws {
        let fixture = try Fixture()
        let location = try fixture.location()
        let first = try CommandEndpointLease(location: location)
        defer { first.release() }
        try first.verifyOwnership()
        #expect(throws: CommandEndpointError.instanceBusy) { try CommandEndpointLease(location: location) }
        try first.verifyOwnership()
        let lock = location.directory.appendingPathComponent("lock")
        #expect(FileManager.default.fileExists(atPath: lock.path))
        first.release()
        first.release()
        #expect(throws: CommandEndpointError.identityChanged) { try first.verifyOwnership() }
        let next = try CommandEndpointLease(location: location)
        defer { next.release() }
        try next.verifyOwnership()
        #expect(!FileManager.default.fileExists(atPath: location.socketPath))
    }

    @Test func permissiveRuntimeAndEndpointDirectoriesAreRefused() throws {
        let fixture = try Fixture()
        let location = try fixture.prepareDirectory()
        #expect(chmod(fixture.root.path, 0o755) == 0)
        #expect(throws: CommandEndpointError.insecureDirectory) { try CommandEndpointLease(location: location) }
        #expect(chmod(fixture.root.path, 0o700) == 0)
        #expect(chmod(location.directory.path, 0o750) == 0)
        #expect(throws: CommandEndpointError.insecureDirectory) { try CommandEndpointLease(location: location) }
    }

    @Test func directoryAndLockSymlinksAreNeverFollowedOrDeleted() throws {
        let fixture = try Fixture()
        let location = try fixture.location()
        let target = fixture.root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: location.directory, withDestinationURL: target)
        #expect(throws: CommandEndpointError.insecureDirectory) { try CommandEndpointLease(location: location) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: location.directory.path) == target.path)
        try FileManager.default.removeItem(at: location.directory)
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let data = target.appendingPathComponent("data")
        try Data("retain".utf8).write(to: data)
        let lock = location.directory.appendingPathComponent("lock")
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: data)
        #expect(throws: CommandEndpointError.insecureLock) { try CommandEndpointLease(location: location) }
        #expect(try Data(contentsOf: data) == Data("retain".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: lock.path) == data.path)
    }

    @Test func permissiveAndHardLinkedLocksAreRetainedAndRefused() throws {
        let fixture = try Fixture()
        let location = try fixture.prepareDirectory()
        let lock = location.directory.appendingPathComponent("lock")
        try Data().write(to: lock)
        #expect(chmod(lock.path, 0o644) == 0)
        #expect(throws: CommandEndpointError.insecureLock) { try CommandEndpointLease(location: location) }
        #expect(chmod(lock.path, 0o600) == 0)
        let other = fixture.root.appendingPathComponent("other")
        try FileManager.default.linkItem(at: lock, to: other)
        #expect(throws: CommandEndpointError.insecureLock) { try CommandEndpointLease(location: location) }
        #expect(FileManager.default.fileExists(atPath: lock.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func replacedNamedObjectsInvalidateTheHeldLease() throws {
        let fixture = try Fixture()
        let location = try fixture.location()
        let lease = try CommandEndpointLease(location: location)
        defer { lease.release() }
        let lock = location.directory.appendingPathComponent("lock")
        try FileManager.default.moveItem(at: lock, to: location.directory.appendingPathComponent("old-lock"))
        try Data().write(to: lock)
        #expect(chmod(lock.path, 0o600) == 0)
        #expect(throws: CommandEndpointError.identityChanged) { try lease.verifyOwnership() }
        lease.release()
        #expect(FileManager.default.fileExists(atPath: lock.path))
    }

    @Test func fifoLockIsRejectedWithoutWaitingForAPeer() throws {
        let fixture = try Fixture()
        let location = try fixture.prepareDirectory()
        let path = location.directory.appendingPathComponent("lock").path
        #expect(mkfifo(path, 0o600) == 0)
        #expect(throws: CommandEndpointError.insecureLock) { try CommandEndpointLease(location: location) }
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func connectedUnixStreamPeersAreKernelChecked() throws {
        var sockets: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        defer { for socket in sockets where socket >= 0 {
            Darwin.close(socket)
        } }
        try CommandSocketPeer.requireCurrentUser(sockets[0])
        try CommandSocketPeer.requireCurrentUser(sockets[1])
        #expect(throws: CommandEndpointError.invalidPeer) { try CommandSocketPeer.requireCurrentUser(-1) }
        var datagrams: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_DGRAM, 0, &datagrams) == 0)
        defer { for datagram in datagrams where datagram >= 0 {
            Darwin.close(datagram)
        } }
        #expect(throws: CommandEndpointError.invalidPeer) { try CommandSocketPeer.requireCurrentUser(datagrams[0]) }
    }

    @Test func allowACLIsRefusedWithoutRemovingItsEntries() throws {
        let fixture = try Fixture()
        let location = try fixture.prepareDirectory()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow read,search", location.directory.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        let before = try aclText(location.directory.path)
        #expect(throws: CommandEndpointError.insecureDirectory) { try CommandEndpointLease(location: location) }
        #expect(try aclText(location.directory.path) == before)
    }

    private func aclText(_ path: String) throws -> String {
        let acl = try #require(acl_get_file(path, ACL_TYPE_EXTENDED))
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var count: ssize_t = 0
        let text = try #require(acl_to_text(acl, &count))
        defer { acl_free(UnsafeMutableRawPointer(text)) }
        return String(cString: text)
    }
}
