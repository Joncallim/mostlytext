import Foundation

/// Caller-owned identity for one immutable original-source snapshot.
/// Bind it to document lifetime and generation; it is not a renderer cache key.
public struct MathSourceIdentity: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum MathDelimiterStyle: Hashable, Sendable {
    case inline
    case display
}

/// Exact UTF-16 offsets and unchanged body from the original source.
public struct MathSyntaxSpan: Hashable, Sendable {
    public let sourceIdentity: MathSourceIdentity
    public let fullRange: Range<Int>
    public let bodyRange: Range<Int>
    public let expression: String
    public let style: MathDelimiterStyle
}

public struct MathScanResult: Sendable, Equatable {
    public let spans: [MathSyntaxSpan]

    /// The unscanned tail must stay authored text; do not run another math pass.
    public let literalRemainderOffset: Int?
}

public enum MathSyntaxError: Error, Equatable {
    case invalidMaximumSpanCount
    case invalidRegion
    case overlappingRegions
    case invalidExclusion
}
