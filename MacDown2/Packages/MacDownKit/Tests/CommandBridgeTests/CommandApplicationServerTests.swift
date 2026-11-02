@testable import CommandBridge
import Darwin
import Foundation
import Testing

@MainActor
struct CommandApplicationServerTests {
    @Test func realSocketValidatesStdinAndDeliversCloseBeforeAcceptance() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try CommandEndpointLocation(runtimeDirectory: root, productIdentity: "test.server")
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("hello\r\nworld\r".utf8)
        var received: Data?
        let lifetime = UUID()
        let receiver = CommandApplicationReceiver { input, admission in
            received = input.bytes
            #expect(admission.bind(.stdin, lifetime: lifetime))
        }
        let server = CommandApplicationServer(location: location, receiver: receiver)
        defer { server.stop() }
        let request = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(bytes: bytes), wait: true)
        let close = Task { @MainActor in
            while received == nil {
                try await Task.sleep(for: .milliseconds(2))
            }
            receiver.documentClosed(lifetime)
        }
        defer { close.cancel() }
        let result = try await Self.thread {
            let endpoint = try Self.connect(location)
            return try CommandClientExchange.execute(request, stdin: bytes, endpoint: endpoint,
                                                     inputDeadline: .now.advanced(by: .seconds(3)),
                                                     acceptanceDeadline: .now.advanced(by: .seconds(3)))
        }
        try await close.value
        #expect(received == bytes)
        #expect(result == .finished(openedCount: 1, failures: []))
        #expect(server.startupFailure == nil)
    }

    @Test func truncatedAndWrongDigestInputHaveNoAppCallbackAndDoNotKillListener() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try CommandEndpointLocation(runtimeDirectory: root, productIdentity: "test.server")
        var calls = 0
        let receiver = CommandApplicationReceiver { _, admission in
            calls += 1
            #expect(admission.bind(.activation, lifetime: UUID()))
        }
        let server = CommandApplicationServer(location: location, receiver: receiver)
        defer { server.stop() }
        try await Self.thread {
            for complete in [false, true] {
                let endpoint = try Self.connect(location)
                let request = try CommandOpenRequest(
                    paths: [],
                    stdin: CommandStdinDescriptor(bytes: Data("right".utf8))
                )
                try endpoint.connection.writeFrame(CommandRequestCodec.encode(request),
                                                   until: .now.advanced(by: .seconds(2)))
                try endpoint.connection.writeFrame(Data("wrong".utf8), until: .now.advanced(by: .seconds(2)))
                if complete {
                    try endpoint.connection.writeFrame(Data(), until: .now.advanced(by: .seconds(2)))
                    _ = try? endpoint.connection.readFrame(until: .now.advanced(by: .seconds(2)))
                }
                endpoint.connection.close()
            }
        }
        try await Task.sleep(for: .milliseconds(60))
        #expect(calls == 0)
        let request = try CommandOpenRequest(paths: [])
        let outcome = try await Self.thread {
            try CommandClientExchange.execute(request, stdin: nil, endpoint: Self.connect(location),
                                              inputDeadline: .now.advanced(by: .seconds(3)),
                                              acceptanceDeadline: .now.advanced(by: .seconds(3)))
        }
        #expect(outcome == .finished(openedCount: 1, failures: []))
        #expect(calls == 1)
    }

    @Test func eightIncompleteInputsBoundAdmissionAndDisconnectReleasesCapacity() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try CommandEndpointLocation(runtimeDirectory: root, productIdentity: "test.server")
        var calls = 0
        let receiver = CommandApplicationReceiver { _, admission in
            calls += 1
            #expect(admission.bind(.activation, lifetime: UUID()))
        }
        let server = CommandApplicationServer(location: location, receiver: receiver)
        defer { server.stop() }
        let request = try CommandOpenRequest(paths: [])
        let outcome = try await Self.thread {
            var blocked: [CommandConnectedEndpoint] = []
            defer { blocked.forEach { $0.connection.close() } }
            let stalled = try CommandOpenRequest(paths: [], stdin: CommandStdinDescriptor(byteCount: 1,
                                                                                          sha256: String(
                                                                                              repeating: "0",
                                                                                              count: 64
                                                                                          )))
            for _ in 0 ..< 8 {
                let endpoint = try Self.connect(location)
                try endpoint.connection.writeFrame(CommandRequestCodec.encode(stalled),
                                                   until: .now.advanced(by: .seconds(2)))
                blocked.append(endpoint)
            }
            Thread.sleep(forTimeInterval: 0.1)
            return try CommandClientExchange.execute(request, stdin: nil, endpoint: Self.connect(location),
                                                     inputDeadline: .now.advanced(by: .seconds(3)),
                                                     acceptanceDeadline: .now.advanced(by: .seconds(3)))
        }
        #expect(outcome == .rejected(.unavailable))
        #expect(calls == 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while server.activeConnections > 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(server.activeConnections == 0)
        let recovered = try await Self.thread {
            try CommandClientExchange.execute(request, stdin: nil, endpoint: Self.connect(location),
                                              inputDeadline: .now.advanced(by: .seconds(3)),
                                              acceptanceDeadline: .now.advanced(by: .seconds(3)))
        }
        #expect(recovered == .finished(openedCount: 1, failures: []))
    }

    @Test func aDisconnectedWaiterCanReplayWithoutOpeningAgain() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = try CommandEndpointLocation(runtimeDirectory: root, productIdentity: "test.server")
        var opens = 0
        let lifetime = UUID()
        let receiver = CommandApplicationReceiver { _, admission in
            opens += 1
            #expect(admission.bind(.path(0), lifetime: lifetime))
        }
        let server = CommandApplicationServer(location: location, receiver: receiver)
        defer { server.stop() }
        let request = try CommandOpenRequest(paths: ["/one"], wait: true)
        try await Self.thread {
            let endpoint = try Self.connect(location)
            defer { endpoint.connection.close() }
            try endpoint.connection.writeFrame(CommandRequestCodec.encode(request),
                                               until: .now.advanced(by: .seconds(2)))
            let frame = try #require(try endpoint.connection.readFrame(until: .now.advanced(by: .seconds(2))))
            #expect(try CommandReplyCodec.decode(frame) == .accepted(requestID: request.id,
                                                                     openedCount: 1, failures: []))
        }
        let close = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(100))
            receiver.documentClosed(lifetime)
        }
        defer { close.cancel() }
        let result = try await Self.thread {
            try CommandClientExchange.execute(request, stdin: nil, endpoint: Self.connect(location),
                                              inputDeadline: .now.advanced(by: .seconds(3)),
                                              acceptanceDeadline: .now.advanced(by: .seconds(3)))
        }
        try await close.value
        #expect(result == .finished(openedCount: 1, failures: []))
        #expect(opens == 1)
    }

    private nonisolated static func connect(_ location: CommandEndpointLocation) throws
        -> sending CommandConnectedEndpoint {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while true {
            do {
                return try CommandEndpointClient.connect(to: location, until: deadline)
            } catch CommandEndpointError.unavailable(ENOENT) {
                // Listener startup has not published the endpoint yet.
            } catch CommandSocketError.unavailable(ECONNREFUSED) {
                // Retry only before a connection/request exists.
            }
            guard ContinuousClock.now < deadline else { throw CommandSocketError.timedOut }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private nonisolated static func thread<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread { continuation.resume(with: Result { try operation() }) }
        }
    }

    private static func root() throws -> URL {
        var pattern = Array("/private/tmp/mts-XXXXXX".utf8CString)
        let path = try pattern.withUnsafeMutableBufferPointer { buffer in
            guard let start = buffer.baseAddress, let result = mkdtemp(start) else {
                throw CommandSocketError.unavailable(errno)
            }
            return String(cString: result)
        }
        return URL(fileURLWithPath: path)
    }
}
