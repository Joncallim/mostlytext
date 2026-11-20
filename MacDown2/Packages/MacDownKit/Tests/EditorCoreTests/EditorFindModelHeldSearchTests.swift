@testable import EditorCore
import Foundation
import Testing
import TextSearch

/// Handoff regression 5 (#377): a search held across close, reopen and a new query must not authorise replacement,
/// reselect or republish highlights from the retired query's matches; and the search-in-selection boundary must
/// hold for replacements built from the result.
@MainActor
struct EditorFindModelHeldSearchTests {
    @Test func aNonCancelledPathologicalQueryShowsTimeoutAndCannotReplace() async {
        let text = String(repeating: "x", count: 40) + "!"
        let model = EditorFindModel(query: "(x+x+)+y", options: SearchOptions(isRegex: true))

        let published = await model.updateMatches(in: text)

        #expect(published)
        #expect(model.error == .timedOut)
        #expect(model.matches.isEmpty)
        #expect(!model.isSearching)
        #expect(model.replaceAllTransaction(with: "replacement") == nil)
    }

    private func startHeldSearch(_ model: EditorFindModel, in text: String) async -> Task<Bool, Never> {
        let search = Task { await model.updateMatches(in: text) }
        while !model.isSearching {
            await Task.yield()
        }
        return search
    }

    @Test func aSearchHeldAcrossCloseReopenAndANewQueryNeverPublishesOrAuthorisesReplacement() async {
        let pathological = String(repeating: "a", count: 40) + "!"
        let live = "foo bar foo"
        let model = EditorFindModel(query: "(a+)+$")
        model.options = SearchOptions(isRegex: true)
        let held = await startHeldSearch(model, in: pathological)

        model.cancelPendingSearch() // Find closed while the search is in flight
        #expect(!model.isSearching)
        #expect(model.replaceAllTransaction(with: "X") == nil, "no stale match may authorise a replacement")

        // Reopened with a different query against the live document.
        model.options = SearchOptions()
        model.query = "foo"
        let published = await model.updateMatches(in: live)
        let heldPublished = await held.value

        #expect(published)
        #expect(!heldPublished, "the retired search must not publish")
        #expect(model.matches.map(\.range) == [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)])
        let transaction = model.replaceAllTransaction(with: "X")
        #expect(transaction?.replacements.map(\.range) == model.matches.map(\.range))
        #expect(model.matchesAreCurrent(forLiveText: live))
    }

    /// Cross-boundary review F3 (P2): freshness was stamped when a search STARTED, so a search cancelled before it
    /// committed left the previous text's matches stamped as current for the new text.
    @Test func aCancelledSearchLeavesTheEarlierMatchesNotCurrentForTheNewText() async {
        let model = EditorFindModel(query: "(a+)+$")
        model.options = SearchOptions(isRegex: true)
        let earlier = "a"
        await model.updateMatches(in: earlier)
        #expect(model.matchesAreCurrent(forLiveText: earlier))
        let later = String(repeating: "a", count: 40) + "!"
        let held = await startHeldSearch(model, in: later)

        model.cancelPendingSearch()
        _ = await held.value

        #expect(!model.matches.isEmpty, "the earlier matches are retained, uncommitted")
        #expect(!model.matchesAreCurrent(forLiveText: later), "but they do not describe the new text")
    }

    @Test func aCloseWithNoLaterSearchLeavesNothingToReplace() async {
        let model = EditorFindModel(query: "(a+)+$")
        model.options = SearchOptions(isRegex: true)
        let held = await startHeldSearch(model, in: String(repeating: "a", count: 40) + "!")

        model.cancelPendingSearch()
        let published = await held.value

        #expect(!published)
        #expect(model.matches.isEmpty)
        #expect(model.currentMatch == nil)
        #expect(model.replaceCurrentTransaction(with: "X") == nil)
        #expect(model.replaceAllTransaction(with: "X") == nil)
    }

    @Test func aSelectionOnlySearchReplacesOnlyMatchesInsideTheSelectedRange() async {
        let text = "foo foo foo foo"
        let selection = NSRange(location: 4, length: 7) // "foo foo"
        let model = EditorFindModel(query: "foo")
        model.options = SearchOptions(searchesSelectionOnly: true)
        await model.updateMatches(in: text, selection: selection)

        let transaction = model.replaceAllTransaction(with: "X")

        #expect(model.matches.map(\.range) == [NSRange(location: 4, length: 3), NSRange(location: 8, length: 3)])
        #expect(transaction?.replacements.map(\.range) == model.matches.map(\.range))
        for range in transaction?.replacements.map(\.range) ?? [] {
            #expect(NSLocationInRange(range.location, selection) && NSMaxRange(range) <= NSMaxRange(selection))
        }
        // A content change outside the matches still invalidates them for the live text.
        #expect(!model.matchesAreCurrent(forLiveText: "Foo foo foo foo"))
    }
}

/// Cross-feature review (2026-10-11), F4: freshness compared only the text, so in the gap between a query/option edit
/// and the asynchronous recompute starting, Replace All could be built from the previous query's matches.
@MainActor
struct EditorFindModelQueryFreshnessTests {
    @Test func matchesAreNotCurrentOnceTheQueryChangesEvenForTheSameText() async {
        let text = "foo bar foo"
        let model = EditorFindModel(query: "foo")
        await model.updateMatches(in: text)
        #expect(model.matchesAreCurrent(forLiveText: text))

        model.query = "bar" // the recompute has not started yet

        #expect(!model.matchesAreCurrent(forLiveText: text))
    }

    @Test func matchesAreNotCurrentOnceAnOptionChangesEvenForTheSameText() async {
        let text = "Foo foo"
        let model = EditorFindModel(query: "foo")
        await model.updateMatches(in: text)
        #expect(model.matchesAreCurrent(forLiveText: text))

        model.options = SearchOptions(isCaseSensitive: true)

        #expect(!model.matchesAreCurrent(forLiveText: text))
        await model.updateMatches(in: text)
        #expect(model.matchesAreCurrent(forLiveText: text), "and current again after the recompute")
    }
}
