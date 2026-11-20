import Foundation

public struct SearchOptions: Sendable, Equatable {
    public var isRegex: Bool
    public var isCaseSensitive: Bool
    public var isWholeWord: Bool
    /// Whether "find next"/"find previous" navigation should wrap around at
    /// the start/end of the searched buffer. `TextSearchEngine.matches`
    /// itself always returns every match regardless of this flag — wrap
    /// behaviour is a stepping/navigation concern the Slice 5 UI layer
    /// applies on top of the full match list, not something the bulk-match
    /// call needs to know about.
    public var wraps: Bool
    /// Advisory to the caller that only the current selection should be
    /// searched. `TextSearchEngine.matches` has no notion of "the
    /// document" or "the selection" — a caller that wants selection-only
    /// search runs `matches` against the FULL text (so `isWholeWord`'s
    /// boundary check still sees the true surrounding context) and then
    /// filters the result down to matches fully contained in the selection,
    /// rather than searching a pre-sliced substring (boundary-unsafe for
    /// `isWholeWord` — see `EditorFindModel.updateMatches`'s own inline
    /// comment for the empirically-reproduced bug this avoids). This flag
    /// exists so UI state (the search bar's "In Selection" toggle) round-trips
    /// through one `SearchOptions` value rather than needing a second,
    /// parallel piece of state.
    public var searchesSelectionOnly: Bool

    public init(
        isRegex: Bool = false,
        isCaseSensitive: Bool = false,
        isWholeWord: Bool = false,
        wraps: Bool = true,
        searchesSelectionOnly: Bool = false
    ) {
        self.isRegex = isRegex
        self.isCaseSensitive = isCaseSensitive
        self.isWholeWord = isWholeWord
        self.wraps = wraps
        self.searchesSelectionOnly = searchesSelectionOnly
    }
}

public enum SearchQueryError: Error, Equatable, Sendable {
    /// A regex query that failed to compile. Carries a localized,
    /// user-presentable message (from `NSRegularExpression`'s own
    /// diagnostic) — a caller must surface this as a visible diagnostic,
    /// never silently fall back to a zero-result state.
    case invalidRegex(String)
    /// The search was cancelled (superseded, or its owner went away) before it
    /// finished. Whatever it had found is partial and must never be presented
    /// as a complete result (#183 F08).
    case cancelled
    /// ICU spent the allotted time matching a regex. Any matches found so far
    /// are partial and must not authorize a complete search or replacement.
    case timedOut
}

/// One match in whatever buffer was searched. `range` is UTF-16, in the
/// coordinates of the `text` that was passed to `TextSearchEngine.matches`.
public struct SearchMatch: Sendable, Equatable {
    public let range: NSRange

    public init(range: NSRange) {
        self.range = range
    }
}
