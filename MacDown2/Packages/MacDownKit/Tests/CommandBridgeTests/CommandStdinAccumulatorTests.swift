import CommandBridge
import Foundation
import Testing

struct CommandStdinAccumulatorTests {
    @Test func fragmentedUTF8BOMEOLAndNoFinalNewlineRemainExactBytes() throws {
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("🙂\r\n文\rno final newline".utf8)
        var accumulator = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: bytes))
        for byte in bytes {
            _ = try accumulator.receive(Data([byte]))
        }
        guard case let .complete(result) = try accumulator.receive(Data()) else {
            Issue.record("terminator must return accepted bytes"); return
        }
        #expect(result == bytes)
        #expect(accumulator.bufferedBytes == 0)
        try accumulator.finish()
        #expect(throws: CommandProtocolError.invalidState) { try accumulator.receive(Data()) }
    }

    @Test func emptyStdinStillRequiresItsTerminator() throws {
        var accumulator = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: Data()))
        guard case let .complete(result) = try accumulator.receive(Data()) else {
            Issue.record("empty stdin must be admitted"); return
        }
        #expect(result.isEmpty)
        try accumulator.finish()
        var missing = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: Data()))
        #expect(throws: CommandProtocolError.truncatedInput) { try missing.finish() }
    }

    @Test func earlyTerminatorExtraBytesAndDigestMismatchPoisonAndReleaseBuffers() throws {
        let descriptor = try CommandStdinDescriptor(bytes: Data("abc".utf8))
        var early = try CommandStdinAccumulator(descriptor: descriptor)
        _ = try early.receive(Data("a".utf8))
        #expect(throws: CommandProtocolError.stdinLengthMismatch) { try early.receive(Data()) }
        #expect(early.bufferedBytes == 0)
        #expect(throws: CommandProtocolError.invalidState) { try early.finish() }
        var extra = try CommandStdinAccumulator(descriptor: descriptor)
        #expect(throws: CommandProtocolError.stdinLengthMismatch) { try extra.receive(Data("abcd".utf8)) }
        #expect(extra.bufferedBytes == 0)
        var changed = try CommandStdinAccumulator(descriptor: descriptor)
        _ = try changed.receive(Data("xyz".utf8))
        #expect(throws: CommandProtocolError.stdinDigestMismatch) { try changed.receive(Data()) }
        #expect(changed.bufferedBytes == 0)
    }

    @Test(arguments: [Data([0xFF]), Data([0xC0, 0xAF]), Data([0xED, 0xA0, 0x80]), Data([0xF0, 0x9F])])
    func malformedUTF8NeverBecomesLossyText(_ invalid: Data) throws {
        var accumulator = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: invalid))
        _ = try accumulator.receive(invalid)
        #expect(throws: CommandProtocolError.invalidUTF8) { try accumulator.receive(Data()) }
        #expect(accumulator.bufferedBytes == 0)
    }

    @Test func cancellationAndOversizedChunksCannotFinishSuccessfully() throws {
        let data = Data(repeating: 65, count: CommandProtocol.maximumFrameBytes + 1)
        var oversized = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: data))
        #expect(throws: CommandProtocolError.frameTooLarge) { try oversized.receive(data) }
        #expect(oversized.bufferedBytes == 0)
        var cancelled = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: Data("ab".utf8)))
        _ = try cancelled.receive(Data("a".utf8))
        cancelled.cancel()
        #expect(cancelled.bufferedBytes == 0)
        #expect(throws: CommandProtocolError.cancelled) { try cancelled.receive(Data()) }
        #expect(throws: CommandProtocolError.cancelled) { try cancelled.finish() }
    }

    @Test func maximumInputIsAdmittedOnlyWithTheMatchingDeclaredDigest() throws {
        let bytes = Data(repeating: 65, count: CommandProtocol.maximumStdinBytes)
        var accumulator = try CommandStdinAccumulator(descriptor: CommandStdinDescriptor(bytes: bytes))
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + CommandProtocol.maximumFrameBytes, bytes.count)
            _ = try accumulator.receive(bytes[offset ..< end]); offset = end
        }
        #expect(accumulator.bufferedBytes == CommandProtocol.maximumStdinBytes)
        guard case let .complete(result) = try accumulator.receive(Data()) else {
            Issue.record("maximum admitted stream must complete"); return
        }
        #expect(result == bytes)
        #expect(accumulator.bufferedBytes == 0)
        #expect(throws: CommandProtocolError.invalidStdinDescriptor) {
            try CommandStdinDescriptor(byteCount: CommandProtocol.maximumStdinBytes + 1,
                                       sha256: String(repeating: "a", count: 64))
        }
    }
}
