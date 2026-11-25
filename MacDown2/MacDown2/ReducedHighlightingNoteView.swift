import FileCore
import Highlighting
import SwiftUI

/// Why a document's syntax highlighting is reduced (register row H5), for the
/// non-modal note in the status bar.
struct ReducedHighlightingNote: Equatable {
    /// Full highlighting returns automatically at or below this length.
    let restoreAtOrBelowUTF16Units: Int
    let visibleOnly: Bool

    /// `nil` unless `state` is reduced.
    init?(_ state: HighlightingState?) {
        guard let state, state.isReduced,
              let policy = HighlightingSizePolicy.default(for: state.requestedLanguageID)
        else { return nil }
        restoreAtOrBelowUTF16Units = policy.restoreAtOrBelowUTF16Units
        visibleOnly = state.isVisibleOnly
    }

    func explanation(locale: Locale, bundle: Bundle = .main) -> String {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        let restore = restoreAtOrBelowUTF16Units.formatted(.number.locale(locale))
        if visibleOnly {
            return String(
                localized: """
                Highlighting is limited to visible text in this large document. Colour may update after \
                editing or scrolling. The text, editing and search are unaffected. Full highlighting \
                returns automatically once the document is at or below \(restore) UTF-16 units.
                """,
                bundle: bundle,
                locale: locale
            )
        }
        return String(
            localized: """
            Syntax highlighting is off for this large document to keep typing responsive. \
            The text, editing and search are unaffected. Highlighting returns automatically \
            once the document is at or below \(restore) UTF-16 units (roughly that many characters of ordinary text).
            """,
            bundle: bundle,
            locale: locale
        )
    }
}

/// A concise, non-modal indicator; the full explanation is its help text.
struct ReducedHighlightingNoteView: View {
    @Environment(\.locale) private var locale
    let note: ReducedHighlightingNote

    var body: some View {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: .main)
        let title = note.visibleOnly ? String(localized: "Visible highlighting only", bundle: bundle, locale: locale)
            : String(localized: "Highlighting reduced", bundle: bundle, locale: locale)
        let explanation = note.explanation(locale: locale)
        return Label(title, systemImage: "speedometer")
            .labelStyle(.titleAndIcon)
            .fixedSize()
            .help(explanation)
            .accessibilityIdentifier("highlightingReducedNote")
            .accessibilityHint(explanation)
    }
}
