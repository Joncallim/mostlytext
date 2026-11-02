import Foundation

public enum FileByteDecodingError: Error, Sendable, Equatable {
    case invalidByteLimit
    case inputTooLarge(maximumBytes: Int)
}

/// Strict decoding of admitted bytes without opening a file or constructing
/// document, session, recovery or observer state. Callers own the byte budget
/// and the executor on which synchronous decoding runs.
public enum FileByteDecoder {
    public static func decode(
        _ bytes: Data,
        maximumBytes: Int,
        policy: FileDecodingPolicy = .automatic
    ) throws -> FileDecodedPayload {
        guard maximumBytes >= 0 else { throw FileByteDecodingError.invalidByteLimit }
        guard bytes.count <= maximumBytes else {
            throw FileByteDecodingError.inputTooLarge(maximumBytes: maximumBytes)
        }
        // Data slices can retain nonzero indices. The strict byte validators
        // index from zero; take an owned, zero-based copy after admission.
        let snapshot = bytes.withUnsafeBytes { Data($0) }
        return try FileStore().decode(snapshot, policy: policy)
    }
}
