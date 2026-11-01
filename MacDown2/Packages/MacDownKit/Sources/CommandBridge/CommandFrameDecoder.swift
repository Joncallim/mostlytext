import Foundation

/// One owner and at most one admitted frame. The caller retains unconsumed input.
public struct CommandFrameDecoder: Sendable {
    private var header: [UInt8] = []
    private var expectedBytes: Int?
    private var body = Data()
    private enum State { case active, failed, cancelled }
    private var state = State.active

    public init() {}

    public var bufferedBytes: Int {
        header.count + body.count
    }

    public mutating func consume(_ input: Data) throws -> CommandFrameConsumption {
        guard state == .active else {
            throw state == .cancelled ? CommandProtocolError.cancelled : .invalidState
        }
        return try input.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var offset = 0
            if expectedBytes == nil {
                while header.count < 4, offset < bytes.count {
                    header.append(bytes[offset]); offset += 1
                }
                guard header.count == 4 else {
                    return CommandFrameConsumption(consumedBytes: offset, frame: nil)
                }
                let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                guard length <= CommandProtocol.maximumFrameBytes else {
                    discard(state: .failed)
                    throw CommandProtocolError.frameTooLarge
                }
                expectedBytes = Int(length)
            }
            guard let expectedBytes else { throw CommandProtocolError.invalidState }
            let amount = min(expectedBytes - body.count, bytes.count - offset)
            if amount > 0 {
                body.append(contentsOf: bytes[offset ..< offset + amount]); offset += amount
            }
            guard body.count == expectedBytes else {
                return CommandFrameConsumption(consumedBytes: offset, frame: nil)
            }
            let completed = body
            body = Data(); header.removeAll(keepingCapacity: false); self.expectedBytes = nil
            return CommandFrameConsumption(consumedBytes: offset, frame: completed)
        }
    }

    public mutating func finish() throws {
        guard state == .active else {
            throw state == .cancelled ? CommandProtocolError.cancelled : .invalidState
        }
        guard header.isEmpty, expectedBytes == nil else {
            discard(state: .failed)
            throw CommandProtocolError.truncatedInput
        }
    }

    public mutating func cancel() {
        discard(state: .cancelled)
    }

    private mutating func discard(state: State) {
        body = Data(); header.removeAll(keepingCapacity: false); expectedBytes = nil
        self.state = state
    }

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
        let length = UInt32(payload.count)
        var result = Data([
            UInt8((length >> 24) & 255), UInt8((length >> 16) & 255),
            UInt8((length >> 8) & 255), UInt8(length & 255),
        ])
        result.append(payload)
        return result
    }
}
