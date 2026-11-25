import FileCore
import Foundation

/// Plain-string labels and help that the Find bar presents verbatim.
struct FindBarLocalizedCopy {
    let caseSensitive: String
    let wholeWordShort: String
    let wholeWord: String
    let regularExpression: String
    let inSelectionShort: String
    let inSelection: String

    init(locale: Locale, bundle: Bundle = .main) {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        caseSensitive = String(localized: "Case Sensitive", bundle: bundle, locale: locale)
        wholeWordShort = String(localized: "W", bundle: bundle, locale: locale)
        wholeWord = String(localized: "Whole Word", bundle: bundle, locale: locale)
        regularExpression = String(localized: "Regular Expression", bundle: bundle, locale: locale)
        inSelectionShort = String(localized: "Sel", bundle: bundle, locale: locale)
        inSelection = String(localized: "In Selection", bundle: bundle, locale: locale)
    }
}
