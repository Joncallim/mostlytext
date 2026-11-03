import Foundation

/// Private producer storage explicitly selected by the application after its
/// installation migration. There is deliberately no owner-profile default.
public struct ExportRecoveryLocation: Sendable, Equatable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }
}
