import Foundation
import Textual

/// Experimental MATH-ADAPTER feasibility fixture, not production source admission.
enum MathAdapterProbe {
    struct Span: Hashable, Sendable {
        let range: NSRange
        let latex: String
        let style: AnyAttachment.MathStyle
        let identifier: UUID
    }

    struct Reference {
        let label: NSRange
        let suffix: NSRange
    }

    struct Marker {
        let text: String
        let generatedRange: NSRange
        let span: Span
    }

    struct Input {
        let original: String
        let rewritten: String
        let prefix: String
        let markers: [Marker]
    }

    struct Outcome {
        let text: AttributedString
        let fellBack: Bool
    }

    enum Failure: Error {
        case invalidInput, overlappingRanges, namespaceCollision, markerIdentity, markerProvenance
    }

    static func validate(_ range: NSRange, in source: String) throws {
        let count = source.utf16.count
        guard range.location >= 0, range.location <= count, range.length >= 0,
              range.length <= count - range.location, Range(range, in: source) != nil
        else { throw Failure.invalidInput }
    }
}

struct MathAdapterProbeSourceAttribute: AttributedStringKey {
    typealias Value = MathAdapterProbe.Span
    static let name = "MostlyText.MathAdapterProbe.Source"
}
