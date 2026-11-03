import Foundation

/// App-owned document lifetime. Revocation and the final synchronous primary
/// promotion share one lock, so a close cannot slip between the last identity
/// check and publication. Cancellation is checked within that cutoff too.
public final class ExportLifetimeLease: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    public init() {}

    public func revoke() {
        lock.withLock { active = false }
    }

    public func checkActive() throws {
        try lock.withLock {
            guard active else { throw CancellationError() }
        }
    }

    public func withPublicationCutoff<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            guard active else { throw CancellationError() }
            try Task.checkCancellation()
            return try body()
        }
    }

    /// Orders owned cleanup against document publication/revocation. Closing
    /// the origin or cancelling its task does not itself forbid safe cleanup;
    /// the recovery protection must still check the current protected object.
    func withRecoveryCutoff<T>(_ body: () throws -> T) rethrows -> T {
        try lock.withLock(body)
    }
}
