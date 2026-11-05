import Foundation
import Textual

extension MathAdapterProbe {
    private struct Match {
        let range: Range<AttributedString.Index>
        let marker: Marker
    }

    @MainActor
    static func parse(
        _ source: String,
        spans: [Span],
        references: [Reference] = [],
        namespace: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        tamper: ((AttributedString) -> AttributedString)? = nil
    ) -> Outcome {
        do {
            let input = try rewrite(source, spans: spans, references: references, namespace: namespace)
            let parser = AttributedStringMarkdownParser(
                baseURL: nil, options: .init(appliesSourcePositionAttributes: true), syntaxExtensions: []
            )
            let parsed = try parser.attributedString(for: input.rewritten)
            return try Outcome(text: restore(tamper?(parsed) ?? parsed, input: input), fellBack: false)
        } catch {
            return Outcome(text: AttributedString(source), fellBack: true)
        }
    }

    private static func restore(_ parsed: AttributedString, input: Input) throws -> AttributedString {
        let matches = try findMatches(parsed, input: input)
        var result = AttributedString()
        var cursor = parsed.startIndex
        for match in matches {
            result.append(AttributedString(parsed[cursor ..< match.range.lowerBound]))
            let fragment = parsed[match.range]
            try checkProvenance(fragment, marker: match.marker, input: input)
            guard let attributes = fragment.runs.first?.attributes else { throw Failure.markerProvenance }
            var attachment = AttributedString("\u{FFFC}", attributes: attributes)
            let span = match.marker.span
            attachment.textual.attachment = .math(latex: span.latex, style: span.style, sourceID: span.identifier)
            attachment[MathAdapterProbeSourceAttribute.self] = span
            result.append(attachment)
            cursor = match.range.upperBound
        }
        result.append(AttributedString(parsed[cursor ..< parsed.endIndex]))
        return result
    }

    private static func findMatches(_ parsed: AttributedString, input: Input) throws -> [Match] {
        let plain = String(parsed.characters)
        var cursor = plain.startIndex
        var seen = Set<String>()
        var matches: [Match] = []
        while let start = plain.range(of: input.prefix, range: cursor ..< plain.endIndex) {
            guard let end = plain[start.upperBound...].firstIndex(of: "Q") else { throw Failure.markerIdentity }
            let range = start.lowerBound ..< plain.index(after: end)
            let text = String(plain[range])
            guard let marker = input.markers.first(where: { $0.text == text }), seen.insert(text).inserted,
                  let lower = AttributedString.Index(range.lowerBound, within: parsed),
                  let upper = AttributedString.Index(range.upperBound, within: parsed)
            else { throw Failure.markerIdentity }
            matches.append(Match(range: lower ..< upper, marker: marker))
            cursor = range.upperBound
        }
        guard seen.count == input.markers.count else { throw Failure.markerIdentity }
        return matches
    }

    private static func checkProvenance(
        _ fragment: AttributedSubstring, marker: Marker, input: Input
    ) throws {
        for run in fragment.runs {
            let intent = run.inlinePresentationIntent ?? []
            guard !intent.contains(.code), !intent.contains(.inlineHTML), !intent.contains(.blockHTML),
                  let position = run.markdownSourcePosition,
                  let range = Range(position, in: input.rewritten)
            else { throw Failure.markerProvenance }
            if run.presentationIntent?.components.contains(where: {
                if case .codeBlock = $0.kind {
                    return true
                }
                return false
            }) == true {
                throw Failure.markerProvenance
            }
            let sourceRange = NSRange(range, in: input.rewritten)
            guard sourceRange.intersection(marker.generatedRange) == marker.generatedRange
            else { throw Failure.markerProvenance }
        }
    }
}
