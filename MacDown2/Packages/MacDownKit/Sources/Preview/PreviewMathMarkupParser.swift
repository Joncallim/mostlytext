import Foundation
import Textual

/// Restores only source-proven occurrences after the existing native Markdown parse.
public struct PreviewMathMarkupParser: MarkupParser {
    private let input: PreviewMathInput
    private let attachments: [UUID: AnyAttachment]
    private let baseURL: URL?

    public init(input: PreviewMathInput, attachments: [UUID: AnyAttachment], baseURL: URL? = nil) {
        self.input = input
        self.attachments = attachments
        self.baseURL = baseURL
    }

    public func attributedString(for source: String) throws -> AttributedString {
        guard source.utf8.elementsEqual(input.source.utf8) else { return AttributedString(source) }
        do {
            let parser = AttributedStringMarkdownParser(
                baseURL: baseURL, options: .init(appliesSourcePositionAttributes: true), syntaxExtensions: []
            )
            return try restore(parser.attributedString(for: input.rewritten))
        } catch {
            return AttributedString(input.source)
        }
    }

    struct Match {
        let range: Range<AttributedString.Index>
        let marker: PreviewMathInput.Marker
    }

    func restore(_ parsed: AttributedString) throws -> AttributedString {
        let matches = try matches(in: parsed)
        var result = AttributedString()
        var cursor = parsed.startIndex
        for match in matches {
            result.append(AttributedString(parsed[cursor ..< match.range.lowerBound]))
            let fragment = parsed[match.range]
            try checkProvenance(fragment, marker: match.marker)
            guard let attributes = fragment.runs.first?.attributes
            else { throw PreviewMathInput.Failure.markerProvenance }
            let attachment = attachments[match.marker.id]
            var restored = AttributedString(attachment == nil ? match.marker.authoredSource : "\u{FFFC}",
                                            attributes: attributes)
            restored.textual.attachment = attachment
            restored[PreviewMathSourceAttribute.self] = match.marker.id
            result.append(restored)
            cursor = match.range.upperBound
        }
        result.append(AttributedString(parsed[cursor ..< parsed.endIndex]))
        return result
    }

    private func matches(in parsed: AttributedString) throws -> [Match] {
        let scalars = parsed.unicodeScalars
        var indices = Array(scalars.indices)
        indices.append(scalars.endIndex)
        let plain = String(String.UnicodeScalarView(scalars))
        // NSString searches literal UTF-16. Convert through scalar offsets so a Prepend
        // or combining neighbor cannot turn a valid endpoint into a Character boundary.
        let literal = plain as NSString
        var offsets: [Int: AttributedString.Index] = [:]
        var offset = 0
        for (index, scalar) in scalars.enumerated() {
            offsets[offset] = indices[index]
            offset += scalar.utf16.count
        }
        offsets[offset] = scalars.endIndex
        var cursor = 0
        var seen = Set<String>()
        var result: [Match] = []
        while cursor < literal.length {
            let family = literal.range(of: input.family, options: .literal,
                                       range: NSRange(location: cursor, length: literal.length - cursor))
            if family.location == NSNotFound {
                break
            }
            var end = NSMaxRange(family)
            while end < literal.length, (48 ... 57).contains(literal.character(at: end)) {
                end += 1
            }
            guard end > NSMaxRange(family), end < literal.length, literal.character(at: end) == 81
            else { throw PreviewMathInput.Failure.markerIdentity }
            let range = NSRange(location: family.location, length: end + 1 - family.location)
            let text = literal.substring(with: range)
            guard let marker = input.markers[text], seen.insert(text).inserted,
                  let lower = offsets[range.location], let upper = offsets[NSMaxRange(range)]
            else { throw PreviewMathInput.Failure.markerIdentity }
            result.append(Match(range: lower ..< upper, marker: marker))
            cursor = NSMaxRange(range)
        }
        guard seen.count == input.markers.count else { throw PreviewMathInput.Failure.markerIdentity }
        return result
    }

    private func checkProvenance(_ fragment: AttributedSubstring, marker: PreviewMathInput.Marker) throws {
        for run in fragment.runs {
            let intent = run.inlinePresentationIntent ?? []
            guard !intent.contains(.code), !intent.contains(.inlineHTML), !intent.contains(.blockHTML),
                  let position = run.markdownSourcePosition,
                  let range = Range(position, in: input.rewritten)
            else { throw PreviewMathInput.Failure.markerProvenance }
            if run.presentationIntent?.components.contains(where: {
                if case .codeBlock = $0.kind {
                    return true
                }
                return false
            }) == true {
                throw PreviewMathInput.Failure.markerProvenance
            }
            let sourceRange = NSRange(range, in: input.rewritten)
            guard sourceRange.intersection(marker.generatedRange) == marker.generatedRange
            else { throw PreviewMathInput.Failure.markerProvenance }
        }
    }
}

/// Opaque occurrence identity; only the live app snapshot can authorize navigation.
public enum PreviewMathSourceAttribute: AttributedStringKey {
    public typealias Value = UUID
    public static let name = "app.mostlytext.preview-math-source"
}
