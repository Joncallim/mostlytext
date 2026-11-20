import FileCore
import Foundation
import Observation
import TextSearch

// MARK: - Current-document Find state (EPIC-22 §6.14, Slice 5a)

/// Pure find/navigate state for the current-document Find bar. Kept free of
/// any AppKit/SwiftUI/`NSTextView` knowledge so it is directly testable
/// without presenting UI, matching `CommandPaletteModel`'s own established
/// convention for a live, `@Observable` SwiftUI-bound model.
///
/// `TextSearchEngine.matches` itself is pure and stateless — it recomputes
/// the full match list from scratch on every call. This type owns the state
/// a Find bar needs ON TOP of that: the current query/`SearchOptions`, the
/// last-computed match list, which match is "current" for Find Next/
/// Previous, and the wrap-around navigation those two actions apply (§6.14:
/// `SearchOptions.wraps` is real but was, until this slice, consumed
/// nowhere — this is that first consumer).
///
/// This type never mutates live text and never scrolls or selects anything
/// itself — callers read `currentMatch` and act on it via
/// `EditorTextSystem`'s own existing `revealSelection(utf16Range:flash:animated:)`.
/// It also never recomputes `matches` on its own: `query`/`options` changes
/// do NOT auto-trigger a search, because this model has no access to the
/// live document text (that lives in whatever `EditorTextSystem` the Find
/// bar is attached to) — callers must explicitly call `updateMatches(in:)`
/// whenever the query, options, or underlying document text changes.
@MainActor
@Observable
public final class EditorFindModel {
    public var query: String
    public var options: SearchOptions
    /// The current "replace with" text (EPIC-22 §6.14, Slice 5b). Owned
    /// here, not the SwiftUI view, so it survives a tab switch and back via
    /// `EditorFindModelStore`, exactly like `query`/`options` already do.
    public var replacementText = ""
    /// Whether the Find bar is currently docked/visible for this tab. Owned
    /// here (not by the SwiftUI view) so it survives a tab switch and back
    /// via `EditorFindModelStore`'s own per-identity caching, exactly like
    /// `query`/`options`/`matches` already do.
    public var isActive = false
    /// Minted by an explicit user activation and consumed by the first
    /// mounted Find bar. A view remount (for example when returning from
    /// Preview Only) must refresh highlights without becoming a new
    /// navigation intent, and a delayed mount must not mint an intent after
    /// newer folder navigation has already happened.
    public var pendingRevealNavigationToken: UInt?

    public private(set) var matches: [SearchMatch] = []
    public private(set) var currentIndex: Int?
    /// Set when the last `updateMatches(in:)` call failed to compile or finish a regex
    /// query — surfaced by the Find bar as a visible diagnostic, per
    /// `SearchQueryError`'s own doc comment ("never silently fall back to a
    /// zero-result state").
    public private(set) var error: SearchQueryError?
    /// `true` while a search is in flight — surfaced by the Find bar so a
    /// slow (or pathological) query doesn't look like it silently did
    /// nothing while `updateMatches(in:)`'s own `Task.detached` is still
    /// running.
    public private(set) var isSearching = false

    /// Bumped by every `updateMatches(in:)` call, before it hops off-main.
    /// The §6.14/§8 "query-generation counter" — mirrors `FileTreeModel.generation`/
    /// `OutlineController`'s own stale-result guards: whichever call's
    /// result lands last only commits it if its own generation is still the
    /// current one, so a slower, now-superseded search (e.g. the user kept
    /// typing) can never overwrite a newer search's already-committed
    /// result. This does NOT stop the superseded search's own computation —
    /// see `updateMatches(in:)`'s own doc comment on why that isn't
    /// possible for `NSRegularExpression` — only discards its answer.
    private var searchGeneration: UInt64 = 0
    private var searchTask: Task<Result<[SearchMatch], SearchQueryError>, Never>?
    /// The dominant line ending of the text the current matches were computed
    /// against, used to adapt a multi-line replacement.
    private(set) var searchedLineEnding: LineEnding?
    /// Exact identity of the text the current matches were computed against. SwiftUI reports text changes
    /// canonically (Å U+00C5 vs U+212B) and never for marked-text edits, so callers compare this with the live text.
    private var searchedFingerprint: ExactTextFingerprint?
    /// The query/options those matches answer (their recompute starts asynchronously, so text alone is not enough).
    private var searchedInputs: (query: ExactTextFingerprint, options: SearchOptions)?
    /// The retained selection scope those matches answer. A text-change
    /// notification can invalidate or remap this scope before the asynchronous
    /// search refresh starts, even when the live text still has equal bytes.
    private var searchedDomain: NSRange?
    private var searchedScopeLost = false
    /// The range "In Selection" searches, retained across refreshes and
    /// remapped through Replace edits (#183 F03). It is sampled from the live
    /// selection only when a caller passes `selection` to `updateMatches`
    /// (Find opened with the option on, or the option turned on) — never
    /// re-sampled from the current selection, which Find itself changes to the
    /// current match or a caret. `nil` means the whole document.
    public private(set) var searchDomain: NSRange?
    /// `true` when the domain could no longer be tracked (undo/redo, whole-text
    /// replacement) — "In Selection" then matches nothing until re-established.
    public private(set) var searchDomainLost = false

    public init(query: String = "", options: SearchOptions = SearchOptions()) {
        self.query = query
        self.options = options
    }

    public var currentMatch: SearchMatch? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    public var matchCount: Int {
        matches.count
    }

    /// The `EditorSelectionSet` "Select All Matches" (EPIC-22 §6.14, Slice
    /// 5c) installs, or `nil` if there are no matches. Deliberately reuses
    /// `EditorSelectionSet(ranges:primaryIndex:)` directly — the exact,
    /// already-general-purpose constructor Slice 3a/3b's own multi-cursor
    /// work already validated — rather than `EditorTextSystem`'s own,
    /// different, word-based `selectAllOccurrences()` (Slice 3c): that is a
    /// separate, already-shipped feature with its own shortcut and its own
    /// "the word under the caret" contract, sharing nothing with a Find
    /// bar's current query/options-driven match list beyond this one
    /// constructor. `currentIndex` (if any) becomes the resulting
    /// selection's own primary caret, so the match the user was already
    /// looking at stays the visually "active" one among the new selections;
    /// falls back to `0` when there is no current match (e.g. Select All
    /// pressed before ever navigating).
    public var selectionSetForAllMatches: EditorSelectionSet? {
        guard !matches.isEmpty else { return nil }
        // `currentIndex` is never `nil` here in practice: every path that
        // populates a non-empty `matches` (`updateMatches`'s own
        // `nearestIndex` call, `advance(by:)`) also sets `currentIndex` to a
        // real index whenever `matches` is non-empty. The `?? 0` is a
        // defensive fallback for that invariant, not a reachable case — a
        // review of this exact line found the test named for "no current
        // index" didn't actually exercise a nil `currentIndex` at the point
        // this property was read, since `updateMatches` had already set one.
        return EditorSelectionSet(ranges: matches.map(\.range), primaryIndex: currentIndex ?? 0)
    }

    /// Recomputes `matches` against `text` for the current `query`/`options`,
    /// then resolves `currentIndex` to the first match starting AT OR AFTER
    /// `anchor` (typically the live caret position when the bar was opened,
    /// or the previously-current match's own start when re-searching after
    /// an option toggle) — wrapping to the first match overall if `anchor`
    /// is past every match, or `nil` if `anchor` itself is `nil`
    /// (defaulting to the very first match) or there are no matches at all.
    /// A failed or timed-out regex clears `matches`/`currentIndex` and populates
    /// `error` instead of leaving stale results on screen.
    ///
    /// EPIC-22 §6.14/§8: the actual `TextSearchEngine.matches` call runs
    /// inside a `Task.detached`, off this `@MainActor` type's own actor —
    /// required because a regex query is user-supplied and can be
    /// catastrophically slow (pathological backtracking), and this method
    /// used to call `TextSearchEngine.matches` directly, inline, on the main
    /// actor: a hostile PR review of this exact slice confirmed that froze
    /// the ENTIRE app, not just the Find bar, with no way to recover short
    /// of force-quit — exactly the adversarial case §15 lists by name
    /// ("cancellation must actually free the main actor"). `Task.detached`
    /// keeps the main actor free while that computation runs. The matcher
    /// checks cancellation and its execution budget at ICU progress callbacks.
    /// `searchGeneration`
    /// is bumped before the hop so a slower, now-superseded call's result is
    /// discarded rather than published over a newer call's already-committed
    /// one, exactly as §8 specifies. Returns whether this call's result was
    /// actually committed (`false` for a discarded, superseded call) so a
    /// caller can skip redundantly re-announcing state nothing changed.
    /// `selection` is the live caret/selection range, in the same UTF-16
    /// coordinates as `text` — required only to implement
    /// `options.searchesSelectionOnly` (EPIC-22 §6.14, Slice 5c: the first
    /// real consumer of that field, per `SearchOptions`' own doc comment —
    /// `TextSearchEngine.matches` itself has no notion of "the selection,"
    /// so this is where a caller filters the full-document match list down
    /// to the ones fully inside the selection; see the inline comment on the
    /// search call below for why this searches the FULL text and filters,
    /// rather than searching a sliced substring). Ignored unless
    /// `options.searchesSelectionOnly` is true AND `selection` is a real,
    /// non-empty range; a caret (zero-length) or `nil` selection falls back
    /// to searching the whole document rather than producing a confusing,
    /// unexplained zero-result state.
    @discardableResult
    public func updateMatches(
        in text: String,
        selection: NSRange? = nil,
        preferringLocationNear anchor: Int? = nil
    ) async -> Bool {
        searchGeneration &+= 1
        let generation = searchGeneration
        if !options.searchesSelectionOnly {
            searchDomain = nil
            searchDomainLost = false
        } else if let selection, selection.length > 0 {
            searchDomain = selection
            searchDomainLost = false
        }
        let domain = options.searchesSelectionOnly ? searchDomain : nil
        let scopeLost = options.searchesSelectionOnly && searchDomainLost
        let query = query
        let options = options
        isSearching = true
        // A superseded search is cancelled outright (its regex checks for cancellation while backtracking), so rapid
        // edits cannot pile up unbounded regex work (#183 F08).
        searchTask?.cancel()
        let task = Task.detached(priority: .userInitiated) {
            Self.search(text: text, query: query, options: options, domain: domain, scopeLost: scopeLost)
        }
        searchTask = task
        let result = await task.value
        guard generation == searchGeneration else { return false }
        if case .failure(.cancelled) = result {
            // Cancelled without being superseded: partial output is never a complete result; keep the previous matches.
            isSearching = false
            return false
        }
        // Stamped at commit, so a search cancelled first leaves the earlier matches stamped with what they answer.
        searchedLineEnding = LineEndingProfile(detecting: text).dominantEnding
        searchedFingerprint = ExactTextFingerprint(text)
        searchedInputs = (ExactTextFingerprint(query), options)
        searchedDomain = domain
        searchedScopeLost = scopeLost
        switch result {
        case let .success(newMatches):
            matches = newMatches
            error = nil
        case let .failure(searchError):
            matches = []
            error = searchError
        }
        currentIndex = Self.nearestIndex(in: matches, to: anchor)
        isSearching = false
        return true
    }

    /// Whether the matches still apply to `text`: same exact content, same query and options, no search in flight.
    public func matchesAreCurrent(forLiveText text: String) -> Bool {
        let scopeIsCurrent = !options.searchesSelectionOnly
            || (!searchDomainLost && !searchedScopeLost && searchedDomain == searchDomain)
        return !isSearching && searchedFingerprint == ExactTextFingerprint(text)
            && searchedInputs?.query == ExactTextFingerprint(query) && searchedInputs?.options == options
            && scopeIsCurrent
    }

    /// Retires any search in flight (closing Find, evicting the document): the matcher is cancelled and a late result
    /// is discarded, so a dismissed bar never re-highlights or reselects and a pathological regex stops running.
    public func cancelPendingSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    /// The off-main search body. Always searches the FULL text, never a
    /// pre-sliced substring: `domain` only FILTERS the already-computed,
    /// full-document matches to ones fully inside it. Slicing first is
    /// boundary-unsafe for `isWholeWord` (the whole-word check only looks at
    /// characters inside whatever string it is given, so a match at the
    /// slice's own edge was wrongly reported as word-bounded — "precat and
    /// cat" with a selection starting after "pre"); filtering the correct
    /// full-text results is immune to that by construction.
    private nonisolated static func search(
        text: String,
        query: String,
        options: SearchOptions,
        domain: NSRange?,
        scopeLost: Bool
    ) -> Result<[SearchMatch], SearchQueryError> {
        do {
            guard !scopeLost else { return .success([]) }
            let found = try TextSearchEngine.matches(in: text, query: query, options: options)
            guard let domain else { return .success(found) }
            let fullLength = (text as NSString).length
            let location = max(0, min(domain.location, fullLength))
            let length = max(0, min(domain.length, fullLength - location))
            let end = location + length
            return .success(found.filter { $0.range.location >= location && NSMaxRange($0.range) <= end })
        } catch {
            return .failure(error)
        }
    }

    /// Forgets the retained domain (Find closed), so a later session samples afresh.
    public func clearSearchDomain() {
        searchDomain = nil
        searchDomainLost = false
    }

    /// Keeps the retained search domain in step with a text change, whatever
    /// its origin (typing, Replace, a transform, a snippet, Convert Line
    /// Endings), so "In Selection" keeps meaning the range the user chose. A
    /// change with no edit geometry (undo/redo, whole-document replacement)
    /// makes the domain untrustworthy: it is dropped and the scope is reported
    /// lost — the search finds nothing until the user re-establishes it —
    /// rather than silently widening to the whole document.
    public func noteTextChange(_ change: EditorTextChange) {
        guard options.searchesSelectionOnly, let domain = searchDomain else { return }
        switch change {
        case .untracked:
            searchDomain = nil
            searchDomainLost = true
        case let .edit(range, replacementLength):
            let delta = replacementLength - range.length
            let editEnd = NSMaxRange(range)
            if editEnd <= domain.location {
                searchDomain = NSRange(location: max(0, domain.location + delta), length: domain.length)
            } else if range.location < NSMaxRange(domain) {
                let start = min(domain.location, range.location)
                let end = max(NSMaxRange(domain), editEnd) + delta
                searchDomain = NSRange(location: start, length: max(0, end - start))
            }
        }
    }

    /// Moves to the next match, wrapping to the first if `options.wraps` and
    /// already at the last — or staying put (a no-op) at the boundary if
    /// wrap is disabled. Starting from no current match (a fresh search)
    /// goes to the first match. Returns the new `currentMatch`.
    @discardableResult
    public func findNext() -> SearchMatch? {
        advance(by: 1)
    }

    /// The reverse of `findNext()`: starting from no current match goes to
    /// the LAST match (not the first), matching every real editor's own
    /// "Find Previous with nothing selected yet" convention.
    @discardableResult
    public func findPrevious() -> SearchMatch? {
        advance(by: -1)
    }

    @discardableResult
    private func advance(by delta: Int) -> SearchMatch? {
        guard !matches.isEmpty else {
            currentIndex = nil
            return nil
        }
        guard let index = currentIndex else {
            currentIndex = delta > 0 ? 0 : matches.count - 1
            return currentMatch
        }
        let next = index + delta
        guard next < 0 || next >= matches.count else {
            currentIndex = next
            return currentMatch
        }
        guard options.wraps else {
            return currentMatch
        }
        currentIndex = next < 0 ? matches.count - 1 : 0
        return currentMatch
    }

    private static func nearestIndex(in matches: [SearchMatch], to anchor: Int?) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let anchor else { return 0 }
        return matches.firstIndex { $0.range.location >= anchor } ?? 0
    }
}
