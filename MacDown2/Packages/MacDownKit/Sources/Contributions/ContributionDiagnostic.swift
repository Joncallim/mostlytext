import Foundation

/// A renderer-neutral diagnostic a contribution reports about its own
/// result. Always forwarded by callers whether or not the content it
/// describes ends up placed, mirroring `ExportService.ExportDiagnostic`'s
/// existing "diagnostics a contribution carries are always forwarded"
/// contract (epic-14-implementation.md §2.1).
public struct ContributionDiagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    /// Optional original-source metadata from the producer's frozen snapshot.
    /// The consumer must recheck its own current source/lifetime before navigation.
    public let sourceRange: Range<Int>?
    public let sourceID: UUID?
    public let sourceOffset: Int?
    public let code: String?
    /// Used only when even a bounded readable fallback cannot be produced safely.
    public let preventsPublication: Bool

    public init(severity: Severity, message: String, sourceRange: Range<Int>? = nil,
                sourceID: UUID? = nil, sourceOffset: Int? = nil, code: String? = nil,
                preventsPublication: Bool = false) {
        self.severity = severity
        self.message = message
        self.sourceRange = sourceRange
        self.sourceID = sourceID
        self.sourceOffset = sourceOffset
        self.code = code
        self.preventsPublication = preventsPublication
    }
}
