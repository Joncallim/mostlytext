@testable import CommandBridge
import Darwin
import Dispatch
import Foundation
import Synchronization
import Testing

struct CommandEndpointTransportTests {
    func withLocation(_ body: (CommandEndpointLocation) throws -> Void) throws {
        var template = Array("/private/tmp/mtx-XXXXXX".utf8CString)
        let path = try template.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress, let result = mkdtemp(base) else {
                throw CommandEndpointError.unavailable(errno)
            }
            return String(cString: result)
        }
        let root = URL(fileURLWithPath: path)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(CommandEndpointLocation(runtimeDirectory: root, productIdentity: "test.endpoint"))
    }

    func rawSocket(_ location: CommandEndpointLocation, listening: Bool = true) throws -> Int32 {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = try CommandSocketPolling.makeSocket()
        do {
            guard try CommandSocketPolling.withAddress(location.socketPath, {
                Darwin.bind(descriptor, $0, $1)
            }) == 0, chmod(location.socketPath, 0o600) == 0 else {
                throw CommandSocketError.unavailable(errno)
            }
            if listening, Darwin.listen(descriptor, 8) != 0 {
                throw CommandSocketError.unavailable(errno)
            }
            return descriptor
        } catch { Darwin.close(descriptor); throw error }
    }

    private final class ClientWork: Sendable {
        let result = Mutex<Result<UUID, any Error>?>(nil)
        let group = DispatchGroup()

        init(_ location: CommandEndpointLocation, expecting instance: UUID? = nil,
             exchange: Bool = false, timeout: Duration = .seconds(5)) {
            group.enter()
            DispatchQueue.global().async { [self] in
                defer { group.leave() }
                do {
                    let endpoint = try CommandEndpointClient.connect(to: location, expecting: instance,
                                                                     until: .now.advanced(by: timeout))
                    defer { endpoint.connection.close() }
                    if exchange {
                        try endpoint.connection.writeFrame(Data("request".utf8), until: .now.advanced(by: timeout))
                        let response = try endpoint.connection.readFrame(until: .now.advanced(by: timeout))
                        guard response == Data("response".utf8) else { throw CommandProtocolError.invalidResponse }
                    }
                    result.withLock { $0 = .success(endpoint.instanceID) }
                } catch { result.withLock { $0 = .failure(error) } }
            }
        }

        func finish() throws -> UUID {
            guard group.wait(timeout: .now() + 7) == .success else { throw CommandSocketError.timedOut }
            return try #require(result.withLock { $0 }).get()
        }

        deinit { _ = group.wait(timeout: .now() + 7) }
    }

    @Test func realPathnameConnectionExchangesHelloAndFrames() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            defer { listener.close() }
            let client = ClientWork(location, exchange: true)
            let server = try listener.accept(until: .now.advanced(by: .seconds(5)))
            defer { server.close() }
            #expect(try server.readFrame(until: .now.advanced(by: .seconds(5))) == Data("request".utf8))
            try server.writeFrame(Data("response".utf8), until: .now.advanced(by: .seconds(5)))
            #expect(try client.finish() == listener.instanceID)
            let namespace = try CommandEndpointNamespace(location)
            #expect(try namespace.socketIdentity() != nil)
            listener.close()
            listener.close()
            #expect(!FileManager.default.fileExists(atPath: location.socketPath))
            #expect(FileManager.default.fileExists(atPath: location.directory.appendingPathComponent("lock").path))
        }
    }

    @Test func heldLeaseAndLiveUnleasedSocketAreNeverRemoved() throws {
        try withLocation { location in
            let lease = try CommandEndpointLease(location: location)
            #expect(throws: CommandEndpointError.instanceBusy) {
                try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(1)))
            }
            lease.release()
            let raw = try rawSocket(location)
            defer { Darwin.close(raw) }
            let namespace = try CommandEndpointNamespace(location)
            let identity = try namespace.socketIdentity()
            #expect(throws: CommandEndpointError.instanceBusy) {
                try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(1)))
            }
            #expect(try namespace.socketIdentity() == identity)
        }
    }

    @Test func definitelyRefusedSocketCanBeReplacedUnderTheLease() throws {
        try withLocation { location in
            let stale = try rawSocket(location, listening: false)
            Darwin.close(stale)
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            defer { listener.close() }
            let client = ClientWork(location)
            let server = try listener.accept(until: .now.advanced(by: .seconds(5)))
            server.close()
            #expect(try client.finish() == listener.instanceID)
            #expect(try FileManager.default.contentsOfDirectory(atPath: location.directory.path).sorted() == [
                "lock",
                "s",
            ])
        }
    }

    @Test func acceptTimeoutAndCancellationLeaveTheListenerUsable() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            defer { listener.close() }
            #expect(throws: CommandSocketError.timedOut) {
                try listener.accept(until: .now.advanced(by: .milliseconds(10)))
            }
            #expect(throws: CommandSocketError.cancelled) {
                try listener.accept(until: .now.advanced(by: .seconds(1)), isCancelled: { true })
            }
            let client = ClientWork(location)
            let server = try listener.accept(until: .now.advanced(by: .seconds(5)))
            server.close()
            #expect(try client.finish() == listener.instanceID)
            listener.close()
            #expect(throws: CommandSocketError.closed) { try listener.accept(until: .now.advanced(by: .seconds(1))) }
        }
    }

    @Test func clientChecksCancellationBeforeFilesystemAccess() throws {
        try withLocation { location in
            #expect(throws: CommandSocketError.cancelled) {
                try CommandEndpointClient.connect(
                    to: location,
                    until: .now.advanced(by: .seconds(1)),
                    isCancelled: { true }
                )
            }
            #expect(!FileManager.default.fileExists(atPath: location.directory.path))
        }
    }

    @Test func reconnectRefusesADifferentInstanceWithoutSendingARequest() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            defer { listener.close() }
            let client = ClientWork(location, expecting: UUID())
            let server = try listener.accept(until: .now.advanced(by: .seconds(5)))
            defer { server.close() }
            #expect(throws: CommandEndpointError.instanceChanged) { try client.finish() }
            #expect(try server.readFrame(until: .now.advanced(by: .seconds(1))) == nil)
        }
    }

    @Test func nonrespondingAndMalformedHelloCloseTheClient() throws {
        for malformed in [false, true] {
            try withLocation { location in
                let raw = try rawSocket(location)
                defer { Darwin.close(raw) }
                let client = ClientWork(location, timeout: malformed ? .seconds(5) : .milliseconds(250))
                try CommandSocketPolling.wait(raw, event: Int16(POLLIN), deadline: .now.advanced(by: .seconds(2)),
                                              cancelled: { false })
                let accepted = Darwin.accept(raw, nil, nil)
                let server = try CommandSocketConnection(adopting: accepted)
                defer { server.close() }
                if malformed {
                    try server.writeFrame(Data("{\"version\":1,\"type\":\"wrong\",\"instance\":\"bad\"}".utf8),
                                          until: .now.advanced(by: .seconds(1)))
                    #expect(throws: CommandProtocolError.invalidResponse) { try client.finish() }
                } else {
                    #expect(throws: CommandSocketError.timedOut) { try client.finish() }
                }
                #expect(try server.readFrame(until: .now.advanced(by: .seconds(1))) == nil)
            }
        }
    }

    @Test func foreignSocketReplacementSurvivesListenerCleanup() throws {
        try withLocation { location in
            let listener = try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(5)))
            let saved = location.directory.appendingPathComponent("saved")
            try FileManager.default.moveItem(atPath: location.socketPath, toPath: saved.path)
            let foreign = try rawSocket(location)
            defer { Darwin.close(foreign) }
            let namespace = try CommandEndpointNamespace(location)
            let identity = try namespace.socketIdentity()
            listener.close()
            #expect(try namespace.socketIdentity() == identity)
            #expect(FileManager.default.fileExists(atPath: saved.path))
        }
    }

    @Test func symlinkRegularFileHardLinkAndPermissiveSocketArePreserved() throws {
        for kind in ["file", "link", "hardlink", "mode"] {
            try withLocation { location in
                let lease = try CommandEndpointLease(location: location)
                lease.release()
                var raw: Int32 = -1
                defer {
                    if raw >= 0 {
                        Darwin.close(raw)
                    }
                }
                switch kind {
                case "file": try Data("preserve".utf8).write(to: URL(fileURLWithPath: location.socketPath))
                case "link":
                    try FileManager.default.createSymbolicLink(atPath: location.socketPath, withDestinationPath: "lock")
                default:
                    raw = try rawSocket(location)
                    if kind == "hardlink" {
                        try FileManager.default.linkItem(atPath: location.socketPath,
                                                         toPath: location.directory.appendingPathComponent("alias")
                                                             .path)
                    } else {
                        #expect(chmod(location.socketPath, 0o666) == 0)
                    }
                }
                #expect(throws: CommandEndpointError.insecureSocket) {
                    try CommandEndpointListener(location: location, until: .now.advanced(by: .seconds(1)))
                }
                #expect(FileManager.default.fileExists(atPath: location.socketPath))
                #expect(throws: CommandEndpointError.insecureSocket) {
                    try CommandEndpointClient.connect(to: location, until: .now.advanced(by: .seconds(1)))
                }
            }
        }
    }

    @Test func helloIsStrictAndVersioned() throws {
        let id = UUID()
        #expect(try CommandInstanceHello.decode(CommandInstanceHello.encode(instanceID: id)) == id)
        let invalid = [
            "{\"version\":1,\"version\":1,\"type\":\"hello\",\"instance\":\"\(id)\"}",
            "{\"version\":1,\"type\":\"hello\",\"instance\":\"\(id)\",\"extra\":0}",
            "{\"version\":1,\"type\":\"hello\",\"instance\":null}",
            "{\"version\":1,\"type\":\"hello\",\"instance\":\"bad\"}",
        ]
        for text in invalid {
            #expect(throws: CommandProtocolError.invalidResponse) {
                try CommandInstanceHello.decode(Data(text.utf8))
            }
        }
        #expect(throws: CommandProtocolError.unsupportedVersion) {
            try CommandInstanceHello.decode(Data("{\"version\":1.0,\"type\":\"hello\",\"instance\":\"\(id)\"}".utf8))
        }
        #expect(throws: CommandProtocolError.frameTooLarge) {
            try CommandInstanceHello.decode(Data(repeating: 65, count: CommandProtocol.maximumFrameBytes + 1))
        }
        #expect(throws: CommandProtocolError.invalidResponse) { try CommandInstanceHello.decode(Data([255])) }
    }
}
