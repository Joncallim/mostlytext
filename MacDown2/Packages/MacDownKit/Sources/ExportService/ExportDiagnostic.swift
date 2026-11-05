import Foundation

/// A non-fatal or fatal observation made during export composition.
///
/// Derived-content failures and unresolved-resource warnings are reported here
/// so they are visible and reviewable, never silently dropped.
public struct ExportDiagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    public let sourceRange: Range<Int>?
    public let sourceID: UUID?
    public let sourceOffset: Int?
    public let code: String?
    /// A derived producer could not establish safe output or bounded source fallback.
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
