import CommandBridge
@testable import CommandLineSupport
import Darwin
import Dispatch
import Foundation
import Synchronization
import Testing

struct CommandConnectionExchangeTests {
    private final class Peer: Sendable {
        private let group = DispatchGroup()
        private let ready = DispatchSemaphore(value: 0)
        private let failure = Mutex<(any Error)?>(nil)

        init(location: CommandEndpointLocation, request: CommandOpenRequest) throws {
            group.enter()
            Thread.detachNewThread { [self] in
                defer { group.leave() }
                do {
                    let listener = try CommandEndpointListener(
                        location: location,
                        until: .now.advanced(by: .seconds(5))
                    )
                    defer { listener.close() }
                    ready.signal()
                    let peer = try listener.accept(until: .now.advanced(by: .seconds(5)))
                    defer { peer.close() }
                    let bytes = try #require(try peer.readFrame(until: .now.advanced(by: .seconds(5))))
                    #expect(try CommandRequestCodec.fingerprint(CommandRequestCodec.decode(bytes)) ==
                        CommandRequestCodec.fingerprint(request))
                    try peer.writeFrame(CommandReplyCodec.encode(.accepted(requestID: request.id,
                                                                           openedCount: 1, failures: [])),
                                        until: .now.advanced(by: .seconds(5)))
                    try peer.writeFrame(CommandReplyCodec.encode(.finished(requestID: request.id)),
                                        until: .now.advanced(by: .seconds(5)))
                } catch {
                    failure.withLock { $0 = error }
                    ready.signal()
                }
            }
            guard ready.wait(timeout: .now() + 7) == .success else { throw CommandSocketError.timedOut }
            if let error = failure.withLock({ $0 }) {
                throw error
            }
        }

        func finish() throws {
            guard group.wait(timeout: .now() + 7) == .success else { throw CommandSocketError.timedOut }
            if let error = failure.withLock({ $0 }) {
                throw error
            }
        }

        deinit { _ = group.wait(timeout: .now() + 7) }
    }

    @Test func warmAndColdConnectionsExchangeOneRequestWithoutRelaunchOrReplay() async throws {
        for cold in [false, true] {
            var pattern = Array("/private/tmp/mtc-XXXXXX".utf8CString)
            let path = try pattern.withUnsafeMutableBufferPointer { buffer in
                guard let start = buffer.baseAddress, let result = mkdtemp(start) else {
                    throw CommandSocketError.unavailable(errno)
                }
                return String(cString: result)
            }
            let root = URL(fileURLWithPath: path)
            defer { try? FileManager.default.removeItem(at: root) }
            let location = try CommandEndpointLocation(runtimeDirectory: root, productIdentity: "test.cli")
            let request = try CommandOpenRequest(paths: ["/one"], wait: true)
            let peer = Mutex<Peer?>(nil)
            let launches = Mutex(0)
            if !cold {
                let created = try Peer(location: location, request: request)
                peer.withLock { $0 = created }
            }
            let endpoint = try await CommandLineConnection.connect(to: location,
                                                                   until: .now.advanced(by: .seconds(5)), launch: {
                                                                       launches.withLock { $0 += 1 }
                                                                       let created = try Peer(location: location,
                                                                                              request: request)
                                                                       peer.withLock { $0 = created }
                                                                   })
            #expect(try CommandClientExchange.execute(request, stdin: nil, endpoint: endpoint,
                                                      inputDeadline: .now.advanced(by: .seconds(5)),
                                                      acceptanceDeadline: .now.advanced(by: .seconds(5))) ==
                    .finished(openedCount: 1, failures: []))
            #expect(launches.withLock { $0 } == (cold ? 1 : 0))
            let running = try #require(peer.withLock { $0 })
            try running.finish()
        }
    }
}
