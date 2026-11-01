import CommandBridge
import Darwin
import Foundation
import Testing

struct CommandSocketConnectionTests {
    private final class Pair {
        let connection: CommandSocketConnection
        var peer: Int32

        init(sendBuffer: Int32? = nil) throws {
            var descriptors: [Int32] = [-1, -1]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
                throw CommandSocketError.unavailable(errno)
            }
            peer = descriptors[1]
            if var sendBuffer {
                guard setsockopt(descriptors[0], SOL_SOCKET, SO_SNDBUF, &sendBuffer,
                                 socklen_t(MemoryLayout.size(ofValue: sendBuffer))) == 0 else {
                    let error = errno
                    descriptors.forEach { Darwin.close($0) }
                    throw CommandSocketError.unavailable(error)
                }
            }
            do {
                connection = try CommandSocketConnection(adopting: descriptors[0])
            } catch {
                Darwin.close(peer)
                throw error
            }
        }

        deinit {
            if peer >= 0 {
                Darwin.close(peer)
            }
        }

        func endPeer() {
            if peer >= 0 {
                Darwin.close(peer); peer = -1
            }
        }

        func put(_ bytes: Data) throws {
            let count = bytes.withUnsafeBytes { send(peer, $0.baseAddress, $0.count, 0) }
            try #require(count == bytes.count)
        }
    }

    @Test func coalescedEmptyAndUnicodeFramesRemainSeparate() throws {
        let pair = try Pair()
        let payload = Data("Café 漢 🐈".utf8)
        try pair.put(CommandFrameDecoder.encode(Data()) + CommandFrameDecoder.encode(payload))
        #expect(try pair.connection.readFrame(until: .now.advanced(by: .seconds(1))) == Data())
        #expect(try pair.connection.readFrame(until: .now.advanced(by: .seconds(1))) == payload)
        pair.endPeer()
        #expect(try pair.connection.readFrame(until: .now.advanced(by: .seconds(1))) == nil)
        #expect(throws: CommandSocketError.closed) { try pair.connection.readFrame(until: nil) }
    }

    @Test func outgoingFramesHaveExactSharedEncoding() throws {
        let pair = try Pair()
        let payload = Data("source\r\n".utf8)
        try pair.connection.writeFrame(payload, until: .now.advanced(by: .seconds(1)))
        let expected = try CommandFrameDecoder.encode(payload)
        var bytes = [UInt8](repeating: 0, count: expected.count)
        let count = recv(pair.peer, &bytes, bytes.count, MSG_WAITALL)
        #expect(count == expected.count)
        #expect(Data(bytes) == expected)
    }

    @Test(arguments: [Data([0, 0]), Data([0, 0, 0, 3, 65])])
    func partialEOFClosesInsteadOfReturningAFrame(_ bytes: Data) throws {
        let pair = try Pair()
        try pair.put(bytes)
        pair.endPeer()
        #expect(throws: CommandProtocolError.truncatedInput) {
            try pair.connection.readFrame(until: .now.advanced(by: .seconds(1)))
        }
        #expect(throws: CommandSocketError.closed) { try pair.connection.readFrame(until: nil) }
    }

    @Test func oversizedHeaderIsRejectedBeforeBodyAdmission() throws {
        let pair = try Pair()
        try pair.put(Data([0, 1, 0, 1]))
        #expect(throws: CommandProtocolError.frameTooLarge) {
            try pair.connection.readFrame(until: .now.advanced(by: .seconds(1)))
        }
    }

    @Test func timeoutAndCancellationCloseTheOwnedConnection() throws {
        let timed = try Pair()
        #expect(throws: CommandSocketError.timedOut) {
            try timed.connection.readFrame(until: .now.advanced(by: .milliseconds(20)))
        }
        #expect(throws: CommandSocketError.closed) { try timed.connection.readFrame(until: nil) }
        let cancelled = try Pair()
        #expect(throws: CommandSocketError.cancelled) {
            try cancelled.connection.readFrame(until: nil, isCancelled: { true })
        }
        #expect(throws: CommandSocketError.closed) { try cancelled.connection.readFrame(until: nil) }
    }

    @Test func closedPeerWriteDoesNotRaiseSIGPIPE() throws {
        let pair = try Pair()
        pair.endPeer()
        #expect(throws: CommandSocketError.self) {
            try pair.connection.writeFrame(Data([65]), until: .now.advanced(by: .seconds(1)))
        }
    }

    @Test func peerClosedBeforeAdoptionStillAllowsBufferedInputAndSafeWrite() throws {
        var descriptors: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let payload = Data("hello before disconnect".utf8)
        let framed = try CommandFrameDecoder.encode(payload)
        let sent = framed.withUnsafeBytes { send(descriptors[1], $0.baseAddress, $0.count, MSG_NOSIGNAL) }
        Darwin.close(descriptors[1])
        let connection = try CommandSocketConnection(adopting: descriptors[0])
        defer { connection.close() }
        #expect(sent == framed.count)
        #expect(try connection.readFrame(until: .now.advanced(by: .seconds(1))) == payload)
        #expect(throws: CommandSocketError.self) {
            try connection.writeFrame(Data([65]), until: .now.advanced(by: .seconds(1)))
        }
    }

    @Test func cancelledAndOversizedWritesDoNotRemainUsable() throws {
        let pair = try Pair()
        #expect(throws: CommandSocketError.cancelled) {
            try pair.connection.writeFrame(Data([65]), until: .now.advanced(by: .seconds(1)), isCancelled: { true })
        }
        #expect(throws: CommandSocketError.closed) { try pair.connection.readFrame(until: nil) }
        let oversized = try Pair()
        #expect(throws: CommandProtocolError.frameTooLarge) {
            try oversized.connection.writeFrame(Data(repeating: 1, count: CommandProtocol.maximumFrameBytes + 1),
                                                until: .now.advanced(by: .seconds(1)))
        }
    }

    @Test func aStalledPartialFrameTimesOutAndCloses() throws {
        let pair = try Pair()
        try pair.put(Data([0, 0, 0, 3, 65]))
        #expect(throws: CommandSocketError.timedOut) {
            try pair.connection.readFrame(until: .now.advanced(by: .milliseconds(20)))
        }
        #expect(throws: CommandSocketError.closed) { try pair.connection.readFrame(until: nil) }
    }

    @Test func backpressuredPartialWritesHonorTheDeadline() throws {
        let pair = try Pair(sendBuffer: 1024)
        #expect(throws: CommandSocketError.timedOut) {
            try pair.connection.writeFrame(Data(repeating: 65, count: CommandProtocol.maximumFrameBytes),
                                           until: .now.advanced(by: .milliseconds(20)))
        }
        var received = [UInt8](repeating: 0, count: CommandProtocol.maximumFrameBytes + 4)
        let count = recv(pair.peer, &received, received.count, MSG_DONTWAIT)
        #expect(count > 4 && count < received.count, "the kernel accepted a proper prefix before backpressure")
        #expect(Array(received.prefix(4)) == [0, 1, 0, 0])
        #expect(throws: CommandSocketError.closed) { try pair.connection.readFrame(until: nil) }
    }
}
