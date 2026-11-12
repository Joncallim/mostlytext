@testable import EditorCore
import Foundation
import Observation
import Testing

/// EPIC-22 §6.14, Slice 5a — per-identity caching for `EditorFindModel`,
/// mirroring `EditorTextSystemTests`' own store coverage for
/// `EditorTextSystemStore`.
@MainActor
@Suite("EditorFindModelStore (Slice 5a)")
struct EditorFindModelStoreTests {
    @Test("store caches and reuses models by identity")
    func storeReusesByIdentity() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString

        let first = store.model(for: identity)
        first.query = "needle"
        let second = store.model(for: identity)

        #expect(first === second)
        #expect(second.query == "needle")
    }

    @Test("a view that saw no model yet is invalidated when model(for:) creates one")
    func creatingAModelInvalidatesAnObserverOfItsAbsence() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString
        let invalidated = InvalidationFlag()

        withObservationTracking {
            _ = store.existingModel(for: identity)
        } onChange: {
            invalidated.set()
        }
        _ = store.model(for: identity)

        #expect(invalidated.isSet)
    }

    @Test("a fresh model for a never-seen identity starts empty and inactive")
    func freshModelStartsEmptyAndInactive() {
        let store = EditorFindModelStore()
        let model = store.model(for: UUID().uuidString)

        #expect(model.query.isEmpty)
        #expect(model.isActive == false)
        #expect(model.matchCount == 0)
    }

    @Test("existingModel returns nil until a model has been created for that identity")
    func existingModelReturnsNilBeforeCreation() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString

        #expect(store.existingModel(for: identity) == nil)
        _ = store.model(for: identity)
        #expect(store.existingModel(for: identity) != nil)
    }

    @Test("evict removes the cached model for that identity")
    func evictRemovesModel() {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString
        _ = store.model(for: identity)

        store.evict(identity)

        #expect(store.existingModel(for: identity) == nil)
        #expect(store.liveIdentities.isEmpty)
    }

    @Test("evictAll clears every cached model")
    func evictAllClearsEveryModel() {
        let store = EditorFindModelStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString
        _ = store.model(for: idA)
        _ = store.model(for: idB)
        store.rememberQuery("private search")

        store.evictAll()

        #expect(store.liveIdentities.isEmpty)
        #expect(store.recentQueries.isEmpty)
    }

    @Test("recent searches are shared across tabs but not cleared by one tab closing")
    func recentQueriesSurviveTabEviction() {
        let store = EditorFindModelStore()
        let first = UUID().uuidString
        _ = store.model(for: first)
        store.rememberQuery("needle")
        store.evict(first)

        _ = store.model(for: UUID().uuidString)
        #expect(store.recentQueries == ["needle"])
        store.clearRecentQueries()
        #expect(store.recentQueries.isEmpty)
    }

    @Test("recent searches are bounded, newest first, and exact-byte distinct")
    func recentQueriesAreBoundedAndPromoted() {
        let store = EditorFindModelStore()
        store.rememberQuery("")
        store.rememberQuery(String(repeating: "x", count: EditorFindModelStore.maximumRecentQueryBytes + 1))
        #expect(store.recentQueries.isEmpty)
        for index in 0 ... EditorFindModelStore.maximumRecentQueries {
            store.rememberQuery("term \(index)")
        }
        #expect(store.recentQueries.count == EditorFindModelStore.maximumRecentQueries)
        #expect(store.recentQueries.first == "term \(EditorFindModelStore.maximumRecentQueries)")
        #expect(!store.recentQueries.contains("term 0"))

        store.rememberQuery("term 1")
        #expect(store.recentQueries.first == "term 1")
        #expect(store.recentQueries.filter { $0 == "term 1" }.count == 1)

        store.rememberQuery("\u{00C5}")
        store.rememberQuery("\u{212B}")
        #expect(store.recentQueries[0].utf8.elementsEqual("\u{212B}".utf8))
        #expect(store.recentQueries[1].utf8.elementsEqual("\u{00C5}".utf8))
    }

    @Test("store tracks live identities")
    func liveIdentities() {
        let store = EditorFindModelStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString

        _ = store.model(for: idA)
        _ = store.model(for: idB)

        #expect(store.liveIdentities == Set([idA, idB]))
    }

    @Test("a model's state, including isActive, survives an evict-less re-fetch")
    func stateSurvivesReFetch() async {
        let store = EditorFindModelStore()
        let identity = UUID().uuidString
        let model = store.model(for: identity)
        model.query = "cat"
        model.isActive = true
        await model.updateMatches(in: "cat and cat", preferringLocationNear: 0)

        let reFetched = store.model(for: identity)

        #expect(reFetched.isActive)
        #expect(reFetched.matchCount == 2)
    }
}

/// `withObservationTracking`'s `onChange` is `@Sendable`; it fires
/// synchronously on the mutating (main) thread here, guarded by a lock anyway.
private final class InvalidationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}
