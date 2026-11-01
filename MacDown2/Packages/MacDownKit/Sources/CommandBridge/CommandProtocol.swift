import Foundation

public enum CommandProtocol {
    public static let version = 1
    public static let maximumFrameBytes = 65536
    public static let maximumPaths = 32
    public static let maximumPathBytes = 4096
    public static let maximumStdinBytes = 32 * 1024 * 1024
}

public enum CommandProtocolError: Error, Sendable, Equatable {
    case frameTooLarge
    case truncatedInput
    case invalidState
    case cancelled
    case malformedMetadata
    case unsupportedVersion
    case unknownFields
    case invalidRequestID
    case invalidPath
    case tooManyPaths
    case invalidStdinDescriptor
    case stdinLengthMismatch
    case stdinDigestMismatch
    case invalidUTF8
    case reusedRequestID
    case invalidReceipt
    case invalidTransition
    case requestCapacity
    case inputCapacity
    case subscriberCapacity
    case receiptCapacity
}

public struct CommandFrameConsumption: Sendable {
    public let consumedBytes: Int
    public let frame: Data?
}
