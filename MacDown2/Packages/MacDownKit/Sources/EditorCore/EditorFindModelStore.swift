import Foundation
import Observation

/// Caches one ``EditorFindModel`` per tab identity (EPIC-22 §6.14, Slice 5a).
///
/// Mirrors ``EditorTextSystemStore``'s own per-identity caching exactly: a
/// single store is owned per window so that switching tabs and back
/// preserves that tab's own find query/options/match state instead of
/// resetting it, and closing a tab evicts its model so a stale query for a
/// document that no longer exists cannot leak into a future tab that
/// happens to reuse the same identity slot.
///
/// `@Observable` so a view that read `existingModel(for:)` while it was still
/// `nil` re-renders once `model(for:)` creates one. Without it the first ⌃F on
/// a tab created and activated a model the editor pane had never observed, so
/// the Find bar did not appear (found by the first real run of
/// `EditingAssistsUITests`).
@MainActor
@Observable
public final class EditorFindModelStore {
    private var models: [String: EditorFindModel] = [:]
    /// Search terms used in this window, newest first. Keep them in memory so a
    /// private query is not added to settings or restored on the next launch.
    public private(set) var recentQueries: [String] = []

    public static let maximumRecentQueries = 20
    public static let maximumRecentQueryBytes = 4096

    public init() {}

    /// Returns an existing model for `identity`, or `nil` if one has not been
    /// created yet.
    public func existingModel(for identity: String) -> EditorFindModel? {
        models[identity]
    }

    /// Returns an existing model for `identity`, or creates a fresh
    /// (inactive, empty-query) one.
    public func model(for identity: String) -> EditorFindModel {
        if let existing = models[identity] {
            return existing
        }
        let created = EditorFindModel()
        models[identity] = created
        return created
    }

    /// Removes the cached model for `identity`. Call when the tab closes.
    public func evict(_ identity: String) {
        models.removeValue(forKey: identity)
    }

    /// Removes every cached model. Call when the owning window closes.
    public func evictAll() {
        models.removeAll()
        recentQueries.removeAll()
    }

    /// Record a completed Find interaction, not each prefix typed into the live field.
    /// Compare UTF-8 bytes because literal search distinguishes canonically equal strings.
    public func rememberQuery(_ query: String) {
        guard !query.isEmpty, query.utf8.count <= Self.maximumRecentQueryBytes else { return }
        recentQueries.removeAll { $0.utf8.elementsEqual(query.utf8) }
        recentQueries.insert(query, at: 0)
        if recentQueries.count > Self.maximumRecentQueries {
            recentQueries.removeLast(recentQueries.count - Self.maximumRecentQueries)
        }
    }

    public func clearRecentQueries() {
        recentQueries.removeAll()
    }

    /// The identities currently held in the cache. Exposed for testing.
    public var liveIdentities: Set<String> {
        Set(models.keys)
    }
}
