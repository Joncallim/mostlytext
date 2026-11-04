import Foundation

/// Localised text for the existing export alert. Diagnostics remain literal
/// text, in order, while catalog plural rules choose count-bearing copy.
struct ExportDiagnosticPresentation {
    let title: String
    let body: String

    init(messages: [String], bundle: Bundle = .main, locale: Locale = .current) {
        title = String(localized: "Exported with \(messages.count) issues", bundle: bundle, locale: locale)
        let shown = messages.prefix(6)
        var text = shown.joined(separator: "\n")
        let omitted = messages.count - shown.count
        if omitted > 0 {
            text += "\n" + String(localized: "…and \(omitted) more issues.", bundle: bundle, locale: locale)
        }
        body = text
    }
}
