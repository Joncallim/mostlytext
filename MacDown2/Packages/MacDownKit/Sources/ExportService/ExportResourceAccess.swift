import Foundation
import LocalResourceAccess

/// Explicit, retained read authority for one export's relative images. A saved
/// document URL supplies metadata; it never creates this capability implicitly.
/// Opening uses existing process access and does not obtain a wider user grant.
public final class ExportResourceAccess: Sendable, Equatable {
    let directory: DirectoryLease

    public init(openingDirectory url: URL) throws {
        guard url.isFileURL else { throw ResourceReadError.invalidReference }
        directory = try DirectoryLease(opening: url)
    }

    public static func == (lhs: ExportResourceAccess, rhs: ExportResourceAccess) -> Bool {
        lhs === rhs
    }
}
