import Foundation

/// Shared first-party prose; renderer/parser free-text is never user-facing.
public enum MathDiagnosticText {
    public static func message(for kind: MathEquationDiagnostic.Kind) -> String {
        switch kind {
        case .invalidSyntax:
            String(localized: "The equation syntax is incomplete or invalid. Its source is shown.", bundle: .module)
        case .unrecognizedCommand:
            String(localized: "The equation contains an unrecognized command. Its source is shown.", bundle: .module)
        case .unsupportedCharacter:
            String(
                localized: "The equation contains a character this renderer does not support. Its source is shown.",
                bundle: .module
            )
        case .invalidEnvironment:
            String(
                localized: "The equation environment is incomplete or unsupported. Its source is shown.",
                bundle: .module
            )
        case .resourceLimit:
            String(localized: "The equation exceeds a rendering safety limit. Its source is shown.", bundle: .module)
        case .internalFailure:
            String(localized: "The equation parser could not complete its work. Its source is shown.", bundle: .module)
        case .renderingFailed:
            String(localized: "The equation could not be drawn. Its source is shown.", bundle: .module)
        case .noVisibleOutput:
            String(localized: "This valid equation has no visible symbols. Its source is shown.", bundle: .module)
        }
    }

    public static func located(_ kind: MathEquationDiagnostic.Kind, line: Int, column: Int) -> String {
        let message = message(for: kind)
        return String(localized: "Equation at line \(line), column \(column): \(message)", bundle: .module)
    }

    public static var analysisUnavailable: String {
        String(localized: "Math analysis could not be safely completed. Export was stopped.", bundle: .module)
    }

    public static var outputLimit: String {
        String(localized: "The equation output exceeds an export safety limit. Export was stopped.", bundle: .module)
    }

    public static var remainder: String {
        String(localized: "The remaining content is shown as source after a rendering safety limit.", bundle: .module)
    }

    public static var sourceAction: String {
        String(localized: "Show equation source", bundle: .module)
    }

    public static var noticesTitle: String {
        String(localized: "Equation notices", bundle: .module)
    }

    public static func equationLabel(_ source: String, isDisplay: Bool) -> String {
        if isDisplay {
            String(localized: "Display equation: \(source)", bundle: .module)
        } else {
            String(localized: "Inline equation: \(source)", bundle: .module)
        }
    }
}
