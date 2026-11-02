import CryptoKit
import Foundation

public enum CommandStdinProgress: Sendable { case receiving, complete(Data) }

/// Call off MainActor after reserving the declared bytes in connection admission.
public struct CommandStdinAccumulator: Sendable {
    private let descriptor: CommandStdinDescriptor
    private var bytes = Data()
    private var hash = SHA256()
    private enum State { case receiving, complete, failed, cancelled }
    private var state = State.receiving

    public init(descriptor: CommandStdinDescriptor) throws {
        self.descriptor = try CommandStdinDescriptor(byteCount: descriptor.byteCount, sha256: descriptor.sha256)
    }

    public var bufferedBytes: Int {
        bytes.count
    }

    public mutating func receive(_ chunk: Data) throws -> CommandStdinProgress {
        guard state == .receiving else {
            throw state == .cancelled ? CommandProtocolError.cancelled : .invalidState
        }
        do {
            guard chunk.count <= CommandProtocol.maximumFrameBytes else { throw CommandProtocolError.frameTooLarge }
            if chunk.isEmpty {
                return try complete()
            }
            guard chunk.count <= descriptor.byteCount - bytes.count else {
                throw CommandProtocolError.stdinLengthMismatch
            }
            bytes.append(chunk); hash.update(data: chunk)
            return .receiving
        } catch {
            clear(state: .failed)
            throw error
        }
    }

    public mutating func cancel() {
        clear(state: .cancelled)
    }

    public mutating func finish() throws {
        switch state {
        case .complete: return
        case .cancelled: throw CommandProtocolError.cancelled
        case .failed: throw CommandProtocolError.invalidState
        case .receiving:
            clear(state: .failed)
            throw CommandProtocolError.truncatedInput
        }
    }

    private mutating func clear(state: State) {
        bytes = Data(); hash = SHA256(); self.state = state
    }

    private mutating func complete() throws -> CommandStdinProgress {
        guard bytes.count == descriptor.byteCount else { throw CommandProtocolError.stdinLengthMismatch }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == descriptor.sha256 else { throw CommandProtocolError.stdinDigestMismatch }
        guard String(data: bytes, encoding: .utf8) != nil else { throw CommandProtocolError.invalidUTF8 }
        let complete = bytes
        bytes = Data(); state = .complete
        return .complete(complete)
    }
}
