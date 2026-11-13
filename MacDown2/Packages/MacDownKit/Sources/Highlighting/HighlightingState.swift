import Foundation

/// What a document's syntax highlighting is doing, separately from the
/// language it asked for (register row H5). A reduced document keeps its
/// requested language and format; only the presentation changes.
public struct HighlightingState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Tree-sitter highlighting is attached.
        case full
        /// No grammar for the requested language (or none requested): plain
        /// text with the theme's chrome, as before H5.
        case plain
        /// Tree-sitter highlighting is deliberately off for responsiveness;
        /// plain text with the theme's chrome until `Reason` no longer holds.
        case reduced(Reason)
        /// Only the mounted viewport is styled from a bounded Markdown cache.
        /// The full-document Neon highlighter remains detached.
        case visibleOnly(Reason)
    }

    public enum Reason: Equatable, Sendable {
        /// The document grew past `limitUTF16Units` (see
        /// ``HighlightingSizePolicy``). The current length is not part of the
        /// state, so typing in a reduced document does not churn observers.
        case documentTooLarge(limitUTF16Units: Int)
    }

    /// The language the document's format asked for (`nil` = plain text).
    public let requestedLanguageID: String?
    public let mode: Mode

    public init(requestedLanguageID: String?, mode: Mode) {
        self.requestedLanguageID = requestedLanguageID
        self.mode = mode
    }

    public var isReduced: Bool {
        switch mode {
        case .reduced, .visibleOnly:
            true
        case .full, .plain:
            false
        }
    }

    public var isVisibleOnly: Bool {
        if case .visibleOnly = mode {
            return true
        }
        return false
    }
}

/// When a language's tree-sitter highlighting is too expensive to keep on.
///
/// Units are UTF-16 code units, the unit `NSTextStorage.length` reports and
/// the unit tree-sitter is fed in (SwiftTreeSitter parses UTF-16), so the
/// check is O(1) per edit and needs no rescan or byte count of the document.
/// A UTF-8 byte count would differ by up to 3x for CJK text and is not used.
public struct HighlightingSizePolicy: Equatable, Sendable {
    /// Highlighting is reduced once the document is longer than this.
    public let reduceAboveUTF16Units: Int
    /// A reduced document regains full highlighting only once it is at or
    /// below this length (hysteresis: well under the cut-off, so editing
    /// around the cut-off never rebuilds the parser repeatedly)…
    public let restoreAtOrBelowUTF16Units: Int
    /// …and has had no edit for this long.
    public let restoreIdleDelay: Duration

    public init(reduceAboveUTF16Units: Int, restoreAtOrBelowUTF16Units: Int, restoreIdleDelay: Duration) {
        precondition(restoreAtOrBelowUTF16Units < reduceAboveUTF16Units, "restore threshold must sit below the cut-off")
        self.reduceAboveUTF16Units = reduceAboveUTF16Units
        self.restoreAtOrBelowUTF16Units = restoreAtOrBelowUTF16Units
        self.restoreIdleDelay = restoreIdleDelay
    }

    /// Markdown (register row H5). Derived from clean Release runs of
    /// `HighlightBudgetBenchmarkTests` (M3 Pro, 2026-10-15; see
    /// `planning/CLOSURE_REGISTER.md`): with five workloads and edits at the
    /// start, middle and end, every one-character edit stayed within the 50 ms
    /// keystroke budget up to ≈16,400 units (inline-dense p95 48.0 ms), and
    /// long lines at ≈18,300 units exceeded it (50.8 ms). The cut-off is a
    /// conservative step well below that, ≈8,400 units (worst measured cell:
    /// unicode, p95 38.2 ms), rounded down to 8,192, leaving headroom for slower Macs and denser text. Restore is three
    /// quarters of it.
    public static let markdown = HighlightingSizePolicy(
        reduceAboveUTF16Units: 8 * 1024,
        restoreAtOrBelowUTF16Units: 6 * 1024,
        restoreIdleDelay: .seconds(2)
    )

    /// The policy for a highlight language, or `nil` for none (unbounded).
    /// Only Markdown is bounded: its inline injection is what makes a keystroke
    /// superlinear in document size. Other grammars were not measured.
    public static func `default`(for languageID: String?) -> HighlightingSizePolicy? {
        languageID == "markdown" ? .markdown : nil
    }
}
