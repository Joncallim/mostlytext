import CommandBridge
import Foundation
import Testing

struct CommandFrameDecoderTests {
    @Test func everySplitOfAHeaderAndUnicodePayloadProducesExactlyOneFrame() throws {
        let payload = Data("a🙂\n文\r\n".utf8)
        let wire = try CommandFrameDecoder.encode(payload)
        for split in 0 ... wire.count {
            var decoder = CommandFrameDecoder()
            let first = try decoder.consume(wire.prefix(split))
            #expect(first.consumedBytes == split)
            if split == wire.count {
                #expect(first.frame == payload)
            } else {
                #expect(first.frame == nil)
                let last = try decoder.consume(wire.dropFirst(split))
                #expect(last.consumedBytes == wire.count - split)
                #expect(last.frame == payload)
            }
            #expect(decoder.bufferedBytes == 0)
            try decoder.finish()
        }
    }

    @Test func concatenatedFramesReturnOnlyOneAndLeaveTheRemainderWithTheCaller() throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let firstWire = try CommandFrameDecoder.encode(first)
        let wire = try firstWire + CommandFrameDecoder.encode(Data()) + CommandFrameDecoder.encode(second)
        var decoder = CommandFrameDecoder()
        let one = try decoder.consume(wire)
        #expect(one.frame == first)
        #expect(one.consumedBytes == firstWire.count)
        let two = try decoder.consume(wire.dropFirst(one.consumedBytes))
        #expect(two.frame == Data())
        #expect(two.consumedBytes == 4)
        let three = try decoder.consume(wire.dropFirst(one.consumedBytes + two.consumedBytes))
        #expect(three.frame == second)
        #expect(decoder.bufferedBytes == 0)
        try decoder.finish()
    }

    @Test(arguments: [[UInt8](arrayLiteral: 0, 1, 0, 1), [255, 255, 255, 255]])
    func oversizedHeaderFailsBeforeBodyAllocationAndPoisonsTheConnection(_ header: [UInt8]) throws {
        var decoder = CommandFrameDecoder()
        _ = try decoder.consume(Data(header.prefix(3)))
        #expect(decoder.bufferedBytes == 3)
        #expect(throws: CommandProtocolError.frameTooLarge) { try decoder.consume(Data(header.suffix(1))) }
        #expect(decoder.bufferedBytes == 0)
        #expect(throws: CommandProtocolError.invalidState) { try decoder.consume(Data([0, 0, 0, 0])) }
    }

    @Test func maximumFrameSurvivesSmallReadsAndNeverRetainsAnotherCompletedPayload() throws {
        let payload = Data(repeating: 0xA5, count: CommandProtocol.maximumFrameBytes)
        let wire = try CommandFrameDecoder.encode(payload)
        var decoder = CommandFrameDecoder()
        var offset = 0
        var completed: Data?
        while offset < wire.count {
            let end = min(offset + 137, wire.count)
            let result = try decoder.consume(wire[offset ..< end])
            #expect(result.consumedBytes == end - offset)
            #expect(decoder.bufferedBytes <= CommandProtocol.maximumFrameBytes + 4)
            if let frame = result.frame {
                completed = frame
            }
            offset += result.consumedBytes
        }
        #expect(completed == payload)
        #expect(decoder.bufferedBytes == 0)
        #expect(throws: CommandProtocolError.frameTooLarge) {
            try CommandFrameDecoder.encode(Data(repeating: 0, count: CommandProtocol.maximumFrameBytes + 1))
        }
    }

    @Test func truncatedInputAndCancellationReleasePartialBytesAndCannotFinishSuccessfully() throws {
        for partial in [Data([0, 0]), Data([0, 0, 0, 3, 65])] {
            var decoder = CommandFrameDecoder()
            _ = try decoder.consume(partial)
            #expect(throws: CommandProtocolError.truncatedInput) { try decoder.finish() }
            #expect(decoder.bufferedBytes == 0)
            #expect(throws: CommandProtocolError.invalidState) { try decoder.finish() }
        }
        var cancelled = CommandFrameDecoder()
        _ = try cancelled.consume(Data([0, 0, 0, 3, 65]))
        cancelled.cancel()
        #expect(cancelled.bufferedBytes == 0)
        #expect(throws: CommandProtocolError.cancelled) { try cancelled.consume(Data()) }
        #expect(throws: CommandProtocolError.cancelled) { try cancelled.finish() }
    }

    @Test func completedPayloadCannotBeMutatedByTheNextFrame() throws {
        var decoder = CommandFrameDecoder()
        let first = try decoder.consume(CommandFrameDecoder.encode(Data("before".utf8)))
        _ = try decoder.consume(CommandFrameDecoder.encode(Data("after".utf8)))
        #expect(first.frame == Data("before".utf8))
    }
}
