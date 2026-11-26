import Foundation

/// Shared first-party prose; renderer/parser free-text is never user-facing.
public enum MathDiagnosticText {
    private static func localizedBundle(for locale: Locale) -> Bundle {
        let source = Bundle.module
        let preferred = Bundle.preferredLocalizations(from: source.localizations, forPreferences: [locale.identifier])
        guard let language = preferred.first,
              let url = source.url(forResource: language, withExtension: "lproj"),
              let selected = Bundle(url: url) else { return source }
        return selected
    }

    public static func message(for kind: MathEquationDiagnostic.Kind, locale: Locale = .current) -> String {
        switch kind {
        case .invalidSyntax:
            String(
                localized: "The equation syntax is incomplete or invalid. Its source is shown.",
                bundle: localizedBundle(for: locale),
                locale: locale
            )
        case .unrecognizedCommand:
            String(
                localized: "The equation contains an unrecognized command. Its source is shown.",
                bundle: localizedBundle(for: locale),
                locale: locale
            )
        case .unsupportedCharacter:
            String(
                localized: "The equation contains a character this renderer does not support. Its source is shown.",
                bundle: localizedBundle(for: locale), locale: locale
            )
        case .invalidEnvironment:
            String(
                localized: "The equation environment is incomplete or unsupported. Its source is shown.",
                bundle: localizedBundle(for: locale), locale: locale
            )
        case .resourceLimit:
            String(
                localized: "The equation exceeds a rendering safety limit. Its source is shown.",
                bundle: localizedBundle(for: locale),
                locale: locale
            )
        case .internalFailure:
            String(
                localized: "The equation parser could not complete its work. Its source is shown.",
                bundle: localizedBundle(for: locale),
                locale: locale
            )
        case .renderingFailed:
            String(localized: "The equation could not be drawn. Its source is shown.",
                   bundle: localizedBundle(for: locale), locale: locale)
        case .noVisibleOutput:
            String(
                localized: "This valid equation has no visible symbols. Its source is shown.",
                bundle: localizedBundle(for: locale),
                locale: locale
            )
        }
    }

    public static func located(
        _ kind: MathEquationDiagnostic.Kind, line: Int, column: Int, locale: Locale = .current
    ) -> String {
        let message = message(for: kind, locale: locale)
        return String(
            localized: "Equation at line \(line), column \(column): \(message)",
            bundle: localizedBundle(for: locale),
            locale: locale
        )
    }

    public static var analysisUnavailable: String {
        String(localized: "Math analysis could not be safely completed. Export was stopped.", bundle: .module)
    }

    public static var previewAnalysisUnavailable: String {
        previewAnalysisUnavailable()
    }

    public static func previewAnalysisUnavailable(locale: Locale = .current) -> String {
        String(
            localized: "Math analysis could not be safely completed. The authored source is shown.",
            bundle: localizedBundle(for: locale),
            locale: locale
        )
    }

    public static var outputLimit: String {
        String(localized: "The equation output exceeds an export safety limit. Export was stopped.", bundle: .module)
    }

    public static var remainder: String {
        remainder()
    }

    public static func remainder(locale: Locale = .current) -> String {
        String(
            localized: "The remaining content is shown as source after a rendering safety limit.",
            bundle: localizedBundle(for: locale),
            locale: locale
        )
    }

    public static var sourceAction: String {
        sourceAction()
    }

    public static func sourceAction(locale: Locale = .current) -> String {
        String(localized: "Show equation source", bundle: localizedBundle(for: locale), locale: locale)
    }

    public static var noticesTitle: String {
        noticesTitle()
    }

    public static func noticesTitle(locale: Locale = .current) -> String {
        String(localized: "Equation notices", bundle: localizedBundle(for: locale), locale: locale)
    }

    public static func equationLabel(_ source: String, isDisplay: Bool, locale: Locale = .current) -> String {
        if isDisplay {
            String(localized: "Display equation: \(source)", bundle: localizedBundle(for: locale), locale: locale)
        } else {
            String(localized: "Inline equation: \(source)", bundle: localizedBundle(for: locale), locale: locale)
        }
    }
}
