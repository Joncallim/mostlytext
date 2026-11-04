import Foundation

/// Localised rejection copy; composition and source-preservation policy stay in the composer.
enum ExportDerivedDiagnosticText {
    static var nestedDiagram: String {
        String(localized: "a diagram inside a list item or block quote is exported as its source text", bundle: .module)
    }

    static var unsafeSVG: String {
        String(
            localized: "derived SVG identifiers could not be safely isolated; authored source preserved",
            bundle: .module
        )
    }

    static var rendererFailure: String {
        String(localized: "derived contribution failed in its renderer; authored source preserved", bundle: .module)
    }

    static func stale(_ generation: UInt, expected: UInt) -> String {
        String(localized: """
        derived contribution is stale (source generation \(generation) != \
        \(expected)); authored source preserved
        """, bundle: .module)
    }

    static func outsideDocument(_ range: Range<Int>) -> String {
        String(localized: """
        derived contribution range \(String(describing: range)) is outside the document body; \
        authored source preserved
        """, bundle: .module)
    }

    static var emptyRange: String {
        String(localized: "derived contribution range is empty; authored source preserved", bundle: .module)
    }

    static var beyondBody: String {
        String(localized: "derived contribution range exceeds the body; authored source preserved", bundle: .module)
    }

    static var overlappingRange: String {
        String(
            localized: "derived contribution range overlaps another contribution; authored source preserved",
            bundle: .module
        )
    }

    static var emptyHTML: String {
        String(localized: "derived contribution produced no HTML; authored source preserved", bundle: .module)
    }

    static func fragmentLimit(_ count: Int) -> String {
        String(localized: """
        derived contribution exceeds the \(count)-fragment export limit; authored \
        source preserved
        """, bundle: .module)
    }

    static func totalLimit(_ limit: String) -> String {
        String(localized: """
        derived contribution exceeds the \(limit) total derived HTML limit; authored source \
        preserved
        """, bundle: .module)
    }
}
