@testable import CommandBridge
import Darwin
import Dispatch
import Foundation
import Synchronization
import Testing

final class ExchangePeerWork: Sendable {
    private let result = Mutex<Result<Void, any Error>?>(nil)
    private let group = DispatchGroup()

    init(descriptor: Int32, handler: @escaping @Sendable (CommandSocketConnection) throws -> Void) {
        group.enter()
        // Blocking socket peers need their own thread: scheduling them on the
        // same cooperative pool as blocked test tasks can starve every peer.
        Thread.detachNewThread { [self] in
            defer { group.leave() }
            do {
                let connection = try CommandSocketConnection(adopting: descriptor)
                defer { connection.close() }
                try handler(connection)
                result.withLock { $0 = .success(()) }
            } catch { result.withLock { $0 = .failure(error) } }
        }
    }

    func finish() throws {
        guard group.wait(timeout: .now() + 8) == .success else { throw CommandSocketError.timedOut }
        try #require(result.withLock { $0 }).get()
    }

    func drain() {
        _ = group.wait(timeout: .now() + 8)
    }
}

final class ExchangePair {
    let client: CommandSocketConnection
    let server: ExchangePeerWork

    init(_ handler: @escaping @Sendable (CommandSocketConnection) throws -> Void) throws {
        var descriptors: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        do {
            client = try CommandSocketConnection(adopting: descriptors[0])
        } catch {
            Darwin.close(descriptors[1]); throw error
        }
        server = ExchangePeerWork(descriptor: descriptors[1], handler: handler)
    }

    deinit { client.close(); server.drain() }

    func execute(_ request: CommandOpenRequest, stdin: Data? = nil,
                 inputDeadline: ContinuousClock.Instant = .now.advanced(by: .seconds(5)),
                 acceptanceDeadline: ContinuousClock.Instant = .now.advanced(by: .seconds(5)),
                 isCancelled: () -> Bool = { false }) throws -> CommandClientOutcome {
        try CommandClientExchange.execute(request, stdin: stdin,
                                          endpoint: CommandConnectedEndpoint(connection: client, instanceID: UUID()),
                                          inputDeadline: inputDeadline, acceptanceDeadline: acceptanceDeadline,
                                          isCancelled: isCancelled)
    }

    static func readRequest(_ connection: CommandSocketConnection) throws -> CommandOpenRequest {
        let bytes = try #require(try connection.readFrame(until: .now.advanced(by: .seconds(5))))
        return try CommandRequestCodec.decode(bytes)
    }

    static func reply(_ event: CommandReceiptEvent, to connection: CommandSocketConnection) throws {
        try connection.writeFrame(CommandReplyCodec.encode(event), until: .now.advanced(by: .seconds(5)))
    }
}
