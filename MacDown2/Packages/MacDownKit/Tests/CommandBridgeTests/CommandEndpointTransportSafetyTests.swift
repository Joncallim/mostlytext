@testable import CommandBridge
import Darwin
import Foundation
import Synchronization
import Testing

extension CommandEndpointTransportTests {
    @Test func acceptedPeerIsClosedWhenTheSocketPathChangesDuringTheWait() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            defer { listener.close() }
            let client = try CommandSocketPolling.makeSocket()
            defer { Darwin.close(client) }
            try CommandSocketPolling.connect(client, path: location.socketPath,
                                             deadline: .now.advanced(by: .seconds(1)), cancelled: { false })
            let checks = Mutex(0)
            #expect(throws: CommandEndpointError.insecureSocket) {
                try listener.accept(until: .now.advanced(by: .seconds(2)), isCancelled: {
                    let current = checks.withLock { $0 += 1; return $0 }
                    if current == 2 {
                        do {
                            try FileManager.default.moveItem(atPath: location.socketPath,
                                                             toPath: location.directory.appendingPathComponent("saved")
                                                                 .path)
                            try Data("foreign".utf8).write(to: URL(fileURLWithPath: location.socketPath))
                        } catch { Issue.record(error) }
                    }
                    return false
                })
            }
            #expect(try Data(contentsOf: URL(fileURLWithPath: location.socketPath)) == Data("foreign".utf8))
            try CommandSocketPolling.wait(client, event: Int16(POLLIN), deadline: .now.advanced(by: .seconds(1)),
                                          cancelled: { false })
            var byte: UInt8 = 0
            #expect(recv(client, &byte, 1, 0) == 0)
        }
    }

    @Test func expiredActivationDoesNotRetireAStaleEndpoint() throws {
        try withLocation { location in
            let raw = try rawSocket(location, listening: false)
            Darwin.close(raw)
            let namespace = try CommandEndpointNamespace(location)
            let original = try namespace.socketIdentity()
            #expect(throws: CommandSocketError.timedOut) {
                try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(-1)))
            }
            #expect(try namespace.socketIdentity() == original)
        }
    }

    @Test func replacedDirectoryAndForeignPathSurviveClose() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            let saved = location.runtimeDirectory.appendingPathComponent("saved-directory")
            try FileManager.default.moveItem(at: location.directory, to: saved)
            try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try Data("foreign".utf8).write(to: URL(fileURLWithPath: location.socketPath))
            listener.close()
            #expect(try Data(contentsOf: URL(fileURLWithPath: location.socketPath)) == Data("foreign".utf8))
            #expect(FileManager.default.fileExists(atPath: saved.appendingPathComponent("s").path))
        }
    }

    @Test func quarantineVerifiesTheMovedObjectAndRestoresAReplacement() throws {
        try withLocation { location in
            let lease = try CommandEndpointLease(location: location)
            defer { lease.release() }
            let original = try rawSocket(location, listening: false)
            defer { Darwin.close(original) }
            let namespace = try CommandEndpointNamespace(location)
            let identity = try #require(try namespace.socketIdentity())
            var replacement: Int32 = -1
            defer {
                if replacement >= 0 {
                    Darwin.close(replacement)
                }
            }
            #expect(throws: CommandEndpointError.identityChanged) {
                try namespace.retireSocket(expected: identity, beforeMove: {
                    try FileManager.default.moveItem(atPath: location.socketPath,
                                                     toPath: location.directory.appendingPathComponent("original").path)
                    replacement = try rawSocket(location, listening: false)
                })
            }
            #expect(try namespace.socketIdentity() != identity)
            #expect(FileManager.default.fileExists(atPath: location.directory.appendingPathComponent("original").path))
            #expect(try !FileManager.default.contentsOfDirectory(atPath: location.directory.path)
                .contains { $0.hasPrefix("retired-") })
        }
    }

    @Test func socketAllowACLIsRefusedAndPreserved() throws {
        try withLocation { location in
            let raw = try rawSocket(location)
            defer { Darwin.close(raw) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+a", "everyone allow read,write", location.socketPath]
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0)
            #expect(throws: CommandEndpointError.insecureSocket) {
                try CommandEndpointClient.connect(to: location, until: .now.advanced(by: .seconds(1)))
            }
            #expect(throws: CommandEndpointError.insecureSocket) {
                try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(1)))
            }
            #expect(FileManager.default.fileExists(atPath: location.socketPath))
        }
    }
}
