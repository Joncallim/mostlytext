import Foundation

/// Bounds work across a series of contained reads, including rejected files.
/// Positive syscall results are charged before allocation/validation. Each
/// in-flight attempt may read at most one over-limit byte to distinguish EOF.
public final class ResourceReadAccounting: @unchecked Sendable {
    private let lock = NSLock()
    private var attemptsRemaining: Int
    private var bytesRemaining: Int

    public init(maxAttempts: Int, maxBytes: Int) {
        attemptsRemaining = max(0, maxAttempts)
        bytesRemaining = max(0, maxBytes)
    }

    func beginAttempt() throws(ResourceReadError) {
        lock.lock()
        defer { lock.unlock() }
        guard attemptsRemaining > 0, bytesRemaining > 0 else { throw .workLimit }
        attemptsRemaining -= 1
    }

    func readAllowance(upTo maximum: Int) -> Int {
        lock.withLock {
            bytesRemaining >= maximum ? maximum : bytesRemaining + 1
        }
    }

    /// Serialize the short regular-file syscall with its debit. Merely taking
    /// an allowance snapshot would let concurrent readers spend the same bytes.
    func readChunk(upTo maximum: Int, perform: (Int) -> (bytesRead: Int, failure: Int32)) throws(ResourceReadError)
        -> (bytesRead: Int, failure: Int32) {
        lock.lock()
        defer { lock.unlock() }
        let allowance = bytesRemaining >= maximum ? maximum : bytesRemaining + 1
        let result = perform(allowance)
        guard result.bytesRead > 0 else { return result }
        guard result.bytesRead <= bytesRemaining else {
            bytesRemaining = 0
            throw .workLimit
        }
        bytesRemaining -= result.bytesRead
        return result
    }
}
