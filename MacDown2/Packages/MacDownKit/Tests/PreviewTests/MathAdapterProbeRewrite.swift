import Foundation

extension MathAdapterProbe {
    private struct Edit {
        let range: NSRange
        let replacement: String
        let span: Span?
    }

    static func rewrite(
        _ source: String,
        spans: [Span],
        references: [Reference] = [],
        namespace: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) throws -> Input {
        guard source.utf16.count <= 500_000, spans.count <= 100, references.count <= spans.count,
              Set(spans.map(\.identifier)).count == spans.count,
              !namespace.isEmpty, namespace.utf8.count <= 64,
              namespace.utf8
              .allSatisfy({ (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) })
        else { throw Failure.invalidInput }
        let prefix = "MTEQ" + namespace + "Z"
        guard !source.contains(prefix) else { throw Failure.namespaceCollision }
        let units = Array(source.utf16)
        var edits: [Edit] = []
        for (index, span) in spans.enumerated() {
            try validate(span.range, in: source)
            let delimiter = span.style == .inline ? "$" : "$$"
            guard !span.latex.isEmpty, slice(units, span.range) == delimiter + span.latex + delimiter
            else { throw Failure.invalidInput }
            edits.append(Edit(range: span.range, replacement: prefix + String(index) + "Q", span: span))
        }
        for reference in references {
            try edits.append(referenceEdit(reference, source: source, units: units, spans: spans))
        }
        return try apply(edits, source: source, units: units, prefix: prefix)
    }

    private static func referenceEdit(
        _ reference: Reference, source: String, units: [UInt16], spans: [Span]
    ) throws -> Edit {
        try validate(reference.label, in: source)
        try validate(reference.suffix, in: source)
        guard reference.label.length > 0, reference.label.location > 0,
              units[reference.label.location - 1] == 91,
              reference.suffix.location == reference.label.upperBound + 1,
              units[reference.label.upperBound] == 93,
              reference.suffix.length == 0 || slice(units, reference.suffix) == "[]",
              spans.contains(where: { reference.label.intersection($0.range) == $0.range })
        else { throw Failure.invalidInput }
        return Edit(range: reference.suffix, replacement: "[" + slice(units, reference.label) + "]", span: nil)
    }

    private static func apply(_ edits: [Edit], source: String, units: [UInt16], prefix: String) throws -> Input {
        var rewritten = ""
        var markers: [Marker] = []
        var originalOffset = 0
        var generatedOffset = 0
        var previousLocation: Int?
        for edit in edits.sorted(by: { $0.range.location < $1.range.location }) {
            guard edit.range.location >= originalOffset, edit.range.location != previousLocation
            else { throw Failure.overlappingRanges }
            previousLocation = edit.range.location
            let length = edit.range.location - originalOffset
            rewritten += slice(units, NSRange(location: originalOffset, length: length))
            generatedOffset += length
            let replacementLength = edit.replacement.utf16.count
            if let span = edit.span {
                markers.append(Marker(text: edit.replacement,
                                      generatedRange: NSRange(location: generatedOffset, length: replacementLength),
                                      span: span))
            }
            rewritten += edit.replacement
            generatedOffset += replacementLength
            originalOffset = edit.range.upperBound
        }
        rewritten += slice(units, NSRange(location: originalOffset, length: units.count - originalOffset))
        return Input(original: source, rewritten: rewritten, prefix: prefix, markers: markers)
    }

    private static func slice(_ units: [UInt16], _ range: NSRange) -> String {
        String(decoding: units[range.location ..< range.upperBound], as: UTF16.self)
    }
}
