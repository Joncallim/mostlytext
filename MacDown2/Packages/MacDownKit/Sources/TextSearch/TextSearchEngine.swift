import Foundation

/// Pure, synchronous, single-buffer search — used directly by
/// current-document find on a bounded buffer, and per-file by
/// `WorkspaceSearchEngine` (folder search) inside its own cancellable
/// off-main task. Never touches AppKit, a window, or a document model.
public enum TextSearchEngine {
    static let regexMatchBudget: Duration = .seconds(2)

    /// Every match of `query` in `text`, honoring `options`. Returns an
    /// empty array for an empty query (never an error — an empty query is
    /// not a malformed one, it simply matches nothing) or when the query
    /// truly does not occur. A regex can throw for invalid syntax,
    /// cancellation or an expired execution budget; partial matches are never
    /// returned as complete results.
    ///
    /// `matchLimit`, when non-`nil`, stops scanning as soon as that many
    /// matches have been found, rather than finding every match and only
    /// discarding the excess afterward — needed so a single pathological
    /// file (e.g. a common single character repeated millions of times)
    /// cannot defeat `WorkspaceSearchEngine`'s own bounded-accumulation
    /// requirement (issue #112) by forcing a full-file, unbounded
    /// `[SearchMatch]` allocation before its result is truncated. `nil` (the
    /// default) does not cap result count. Regex execution still has a
    /// separate time budget.
    public static func matches(
        in text: String,
        query: String,
        options: SearchOptions,
        matchLimit: Int? = nil
    ) throws(SearchQueryError) -> [SearchMatch] {
        try matches(in: text, query: query, options: options, matchLimit: matchLimit,
                    regexDeadline: ContinuousClock.now.advanced(by: regexMatchBudget))
    }

    /// Package-internal entry point lets folder search share its whole-run
    /// deadline with every file, while keeping one matcher and one public API.
    static func matches(
        in text: String,
        query: String,
        options: SearchOptions,
        matchLimit: Int?,
        regexDeadline: ContinuousClock.Instant
    ) throws(SearchQueryError) -> [SearchMatch] {
        guard !query.isEmpty else { return [] }
        if options.isRegex {
            return try regexMatches(in: text, pattern: query, options: options,
                                    matchLimit: matchLimit, deadline: regexDeadline)
        }
        return literalMatches(in: text, query: query, options: options, matchLimit: matchLimit)
    }

    // MARK: - Literal

    private static func literalMatches(
        in text: String,
        query: String,
        options: SearchOptions,
        matchLimit: Int?
    ) -> [SearchMatch] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }
        var compareOptions: NSString.CompareOptions = options.isCaseSensitive ? [] : [.caseInsensitive]
        // `.literal` disables Unicode canonical-equivalence matching (e.g.
        // treating a precomposed "é" and "e" + combining acute as equal) —
        // MacDown 2's other text-fidelity code (FileStore's decode path)
        // never performs canonical normalization either, so search must not
        // quietly do so.
        compareOptions.insert(.literal)

        var results: [SearchMatch] = []
        var searchStart = 0
        while searchStart <= nsText.length {
            if let matchLimit, results.count >= matchLimit {
                break
            }
            let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
            let found = nsText.range(of: query, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound else { break }
            if !options.isWholeWord || isWholeWordMatch(found, in: nsText) {
                results.append(SearchMatch(range: found))
            }
            // Advance past the start of this match by at least one UTF-16
            // unit even for a (theoretically impossible, since query is
            // non-empty) zero-length match, so the loop always terminates.
            searchStart = found.location + max(found.length, 1)
        }
        return results
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    private static func isWholeWordMatch(_ range: NSRange, in text: NSString) -> Bool {
        if range.location > 0, let before = scalar(endingAt: range.location, in: text), isWordScalar(before) {
            return false
        }
        let end = range.location + range.length
        if end < text.length, let after = scalar(startingAt: end, in: text), isWordScalar(after) {
            return false
        }
        return true
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        wordCharacters.contains(scalar)
    }

    /// The scalar ending at `index` (the previous character), handling
    /// surrogate halves as one scalar — a local equivalent of
    /// `EditorCore`'s `MarkdownEditingAssistEngine.scalar(before:in:)`,
    /// duplicated deliberately rather than shared: `TextSearch` must not
    /// depend on `EditorCore` (one-directional dependency, see
    /// `planning/epic-22-implementation.md` §5.1).
    private static func scalar(endingAt index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index > 0, index <= text.length else { return nil }
        var start = index - 1
        var length = 1
        let unit = text.character(at: start)
        if unit >= 0xDC00, unit <= 0xDFFF, start > 0 {
            let high = text.character(at: start - 1)
            if high >= 0xD800, high <= 0xDBFF {
                start -= 1
                length = 2
            }
        }
        return leadingScalar(in: text, at: start, length: length)
    }

    private static func scalar(startingAt index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index >= 0, index < text.length else { return nil }
        let unit = text.character(at: index)
        let length = (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) ? 2 : 1
        return leadingScalar(in: text, at: index, length: length)
    }

    private static func leadingScalar(in text: NSString, at index: Int, length: Int) -> Unicode.Scalar? {
        text.substring(with: NSRange(location: index, length: length)).unicodeScalars.first
    }

    // MARK: - Regex

    private static func regexMatches(
        in text: String,
        pattern: String,
        options: SearchOptions,
        matchLimit: Int?,
        deadline: ContinuousClock.Instant
    ) throws(SearchQueryError) -> [SearchMatch] {
        // `^`/`$` match at every line boundary, as in every code editor; without
        // this they only matched at the start/end of the whole document, so
        // `^# ` found one heading in a document of three.
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.isCaseSensitive {
            regexOptions.insert(.caseInsensitive)
        }
        // Whole-word for regex wraps the user's pattern in word-boundary
        // anchors rather than requiring the user to write `\b` themselves —
        // matching how the "Whole Word" checkbox composes with a literal
        // query.
        let effectivePattern = options.isWholeWord ? "\\b(?:\(pattern))\\b" : pattern

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: effectivePattern, options: regexOptions)
        } catch {
            throw SearchQueryError.invalidRegex(error.localizedDescription)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var results: [SearchMatch] = []
        var wasCancelled = false
        var timedOut = false
        // `.reportProgress` makes ICU call back periodically even while a
        // pathological pattern is backtracking without producing a match; that
        // is the only chance to honour cancellation or expiry, so both are
        // handled *before*
        // `guard let match` (a progress call carries no match).
        regex.enumerateMatches(in: text, options: [.reportProgress], range: fullRange) { match, _, stop in
            if Task.isCancelled {
                wasCancelled = true
                stop.pointee = true
                return
            }
            if ContinuousClock.now >= deadline {
                timedOut = true
                stop.pointee = true
                return
            }
            guard let match else { return }
            // Admitted (CRLF-normalised) BEFORE it is charged against the cap: raw matches that normalisation later
            // drops must not use up the limit, or `(?=\n)|X` over `\r\n\r\nX` with limit 2 never reached X and the
            // folder search's remaining+1 completeness probe reported a false "complete".
            guard let admitted = admittingCRLFPairsWhole(match.range, after: results.last, in: nsText) else { return }
            results.append(admitted)
            if let matchLimit, results.count >= matchLimit {
                stop.pointee = true
            }
        }
        if wasCancelled || Task.isCancelled {
            throw SearchQueryError.cancelled
        }
        if timedOut || ContinuousClock.now >= deadline {
            throw SearchQueryError.timedOut
        }
        return results
    }

    /// ICU treats the CR and LF of a CRLF pair as two characters, so `\n` matches only the LF and `.*` can match
    /// between them; a replacement then leaves a lone CR (or inserts text inside the pair). A match that starts at the
    /// LF of a pair grows to include the CR (so "replace newline" replaces the whole terminator), and an empty match
    /// between the two is dropped. A match ending between them is left alone: `\r` is a legitimate way to strip CRs.
    /// A match the growth would overlap with its predecessor is dropped. `nil` means "not a match".
    private static func admittingCRLFPairsWhole(
        _ range: NSRange,
        after last: SearchMatch?,
        in text: NSString
    ) -> SearchMatch? {
        func splitsPair(at index: Int) -> Bool {
            index > 0 && index < text.length && text.character(at: index - 1) == 0x0D && text
                .character(at: index) == 0x0A
        }
        var start = range.location
        let end = NSMaxRange(range)
        if start == end, splitsPair(at: start) {
            return nil
        }
        // Grow back over the CR unless the previous match already covers it (`[\r\n]`, `\s`, `\r|\n`): then the LF
        // is its own match and must be kept, or Replace All would drop the LF half of the line ending.
        if splitsPair(at: start), !(last.map { NSMaxRange($0.range) >= start } ?? false) {
            start -= 1
        }
        if let last, start < NSMaxRange(last.range) {
            return nil
        }
        return SearchMatch(range: NSRange(location: start, length: end - start))
    }
}
