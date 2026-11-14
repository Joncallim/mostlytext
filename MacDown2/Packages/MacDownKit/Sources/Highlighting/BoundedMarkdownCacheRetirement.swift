import Foundation

/// Releases an obsolete immutable parse cache after the storage callback has
/// returned. At most two caches may await worker release; overflow releases
/// synchronously, preserving a fixed memory bound at the cost of a possible
/// slow input in that rare case. The mounted budget covers the ordinary path,
/// and the overflow behavior is exercised separately.
@MainActor
final class BoundedMarkdownCacheRetirement {
    static let shared = BoundedMarkdownCacheRetirement()

    private(set) var inFlightCount = 0
    private(set) var overflowCount = 0

    /// Test seams for exact release-before-slot ordering and forced overflow.
    var workerHoldForTesting: (@Sendable () async -> Void)?
    var onSlotReleasedForTesting: (() -> Void)?

    /// The box has one mutable owner after transfer: its detached worker.
    /// A `MarkdownSectionCache` holds immutable `Tree: Sendable` snapshots and
    /// `Node` values that only reference those trees. SwiftTreeSitter does not
    /// declare `Node` Sendable, so this narrow one-owner transfer is explicit.
    private final class Box<Value>: @unchecked Sendable {
        private var value: Value?

        init(_ value: Value) {
            self.value = value
        }

        func release() {
            value = nil
        }
    }

    func retire(_ value: some Any) {
        guard inFlightCount < 2 else {
            overflowCount += 1
            return
        }
        inFlightCount += 1
        let box = Box(value)
        let hold = workerHoldForTesting
        // Start the worker on the next main turn. This guarantees that the
        // caller's temporary strong reference is gone before `box.release()`
        // can perform the final tree destruction on the utility executor.
        DispatchQueue.main.async { [weak self, box] in
            Task.detached(priority: .utility) { [weak self, box] in
                await hold?()
                box.release()
                await MainActor.run {
                    self?.inFlightCount -= 1
                    self?.onSlotReleasedForTesting?()
                }
            }
        }
    }
}
