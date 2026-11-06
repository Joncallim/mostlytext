import EditorCore
import FileCore
import Foundation
import SwiftUI
import Themes

/// The editor status bar (epic-22-implementation.md §6.7, §17 Slice 2b).
///
/// Shows line/column, selected/document character and word count, and
/// indentation mode/width — the three status items with no forward
/// dependency on a later slice. §6.7's scope-correction note records why
/// the epic issue's other status-bar items (multi-selection count,
/// line-ending state, encoding, syntax mode) are deliberately deferred to
/// Slices 3/8/9 rather than stubbed here.
struct EditorStatusBarView: View {
    /// The live text, uncopied, and its precomputed metrics: a selection-only
    /// re-render does no whole-document work (#183 F16).
    let source: NSString
    let metrics: EditorDocumentMetrics
    let selectedRange: NSRange
    let lineIndex: EditorLineIndex
    let indentationWidth: Int
    let convertsTabsToSpaces: Bool
    let onGoToLine: () -> Void
    /// The document's encoding and what may be done with it; `nil` (the
    /// default) omits the item, e.g. for callers that only render the
    /// original three status items.
    var encoding: EncodingStatusItem?
    /// The document's line-ending state and the conversion action; `nil`
    /// omits the item.
    var lineEnding: LineEndingStatusItem?
    /// The document's syntax mode and its override action; `nil` omits it.
    var syntaxMode: SyntaxModeStatusItem?
    /// Set while the document's syntax highlighting is reduced for size.
    var reducedHighlighting: ReducedHighlightingNote?

    let palette: ResolvedPresentationPalette?

    init(
        source: NSString,
        metrics: EditorDocumentMetrics,
        selectedRange: NSRange,
        lineIndex: EditorLineIndex,
        indentationWidth: Int,
        convertsTabsToSpaces: Bool,
        onGoToLine: @escaping () -> Void,
        encoding: EncodingStatusItem? = nil,
        lineEnding: LineEndingStatusItem? = nil,
        syntaxMode: SyntaxModeStatusItem? = nil,
        reducedHighlighting: ReducedHighlightingNote? = nil,
        palette: ResolvedPresentationPalette? = nil
    ) {
        self.source = source
        self.metrics = metrics
        self.selectedRange = selectedRange
        self.lineIndex = lineIndex
        self.indentationWidth = indentationWidth
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.onGoToLine = onGoToLine
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.syntaxMode = syntaxMode
        self.reducedHighlighting = reducedHighlighting
        self.palette = palette
    }

    /// Convenience for callers (and tests) that only have a `String`.
    init(
        text: String,
        selectedRange: NSRange,
        lineIndex: EditorLineIndex,
        indentationWidth: Int,
        convertsTabsToSpaces: Bool,
        onGoToLine: @escaping () -> Void
    ) {
        self.init(
            source: text as NSString,
            metrics: EditorDocumentMetrics(of: text),
            selectedRange: selectedRange,
            lineIndex: lineIndex,
            indentationWidth: indentationWidth,
            convertsTabsToSpaces: convertsTabsToSpaces,
            onGoToLine: onGoToLine
        )
    }

    /// Not `private`: read directly by `EditorStatusBarViewTests`, which
    /// tests these pure computations without needing a full SwiftUI render
    /// pass (epic-22-implementation.md §6.7's promised status-bar test
    /// coverage).
    var lineColumnText: String {
        let line = lineIndex.line(atUTF16Offset: selectedRange.location)
        let column = lineIndex.column(atUTF16Offset: selectedRange.location, onLine: line, in: source)
        return String(localized: "Ln \(line), Col \(column)", bundle: .main)
    }

    var countText: String {
        if selectedRange.length > 0, NSMaxRange(selectedRange) <= source.length {
            let selectedCharacterCount = source.substring(with: selectedRange).count
            return String(localized: "\(selectedCharacterCount) selected", bundle: .main)
        }
        return String(
            localized: "\(metrics.characterCount) characters, \(metrics.wordCount) words",
            bundle: .main
        )
    }

    var indentationText: String {
        convertsTabsToSpaces
            ? String(localized: "Spaces: \(indentationWidth)", bundle: .main)
            : String(localized: "Tabs: \(indentationWidth)", bundle: .main)
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onGoToLine) {
                Text(lineColumnText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statusBarLineColumn")
            .help("Go to Line/Column")

            Text(countText)
                .accessibilityIdentifier("statusBarCount")

            Spacer()

            if let reducedHighlighting {
                ReducedHighlightingNoteView(note: reducedHighlighting)
            }

            if let syntaxMode {
                SyntaxModeStatusItemView(item: syntaxMode)
            }

            if let encoding {
                EncodingStatusItemView(
                    encoding: encoding.metadata,
                    isChangeable: encoding.isChangeable,
                    onReopen: encoding.onReopen,
                    onSave: encoding.onSave
                )
            }

            if let lineEnding {
                LineEndingStatusItemView(profile: lineEnding.profile, onConvert: lineEnding.onConvert)
            }

            Text(indentationText)
                .accessibilityIdentifier("statusBarIndentation")
        }
        .font(.caption)
        .foregroundStyle(palette.map { Color(nsColor: $0.statusForeground.nsColor) } ?? Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if let palette {
                Color(nsColor: palette.statusBackground.nsColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorStatusBar")
    }

    /// Foundation's own word-boundary logic (`enumerateSubstrings`,
    /// `.byWords`) — no new tokenizer, matching this codebase's established
    /// "reuse Foundation before inventing" pattern elsewhere. Not `private`:
    /// read directly by `EditorStatusBarViewTests`.
    ///
    /// `nonisolated` is required, not cosmetic: as a `static` member of a
    /// `View`-conforming type, this would otherwise inherit `@MainActor`
    /// isolation, and `NSString.enumerateSubstringsInRange:options:usingBlock:`
    /// can invoke its block from a thread that never went through Swift's
    /// executor-hopping machinery (confirmed via crash-log analysis: a real,
    /// intermittent `EXC_BREAKPOINT` in `swift_task_checkIsolatedSwift`,
    /// reproduced by `EditorStatusBarViewTests`). This function touches no
    /// actor-isolated state — only its own parameter and a local variable —
    /// so removing the inherited isolation is correct, not a workaround.
    nonisolated static func wordCount(in text: String) -> Int {
        EditorDocumentMetrics.wordCount(in: text)
    }
}

/// Inputs for the status bar's encoding indicator.
struct EncodingStatusItem {
    let metadata: FileEncodingMetadata
    let isChangeable: Bool
    let onReopen: (String.Encoding) -> Void
    let onSave: (FileEncodingMetadata) -> Void
}

/// Inputs for the status bar's line-ending indicator.
struct LineEndingStatusItem {
    let profile: LineEndingProfile
    let onConvert: (LineEnding) -> Void
}
