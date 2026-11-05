import Foundation

/// Proven, block-local source substitutions prepared before native Markdown parsing.
public struct PreviewMathInput: Sendable {
    public struct Replacement: Sendable {
        public let id: UUID
        public let range: Range<Int>
        public let expectedSource: String

        public init(id: UUID, range: Range<Int>, expectedSource: String) {
            self.id = id
            self.range = range
            self.expectedSource = expectedSource
        }
    }

    public struct SourceEdit: Sendable {
        public let range: Range<Int>
        public let expectedSource: String
        public let replacement: String

        public init(range: Range<Int>, expectedSource: String, replacement: String) {
            self.range = range
            self.expectedSource = expectedSource
            self.replacement = replacement
        }
    }

    public enum Failure: Error, Sendable {
        case invalidRange, sourceMismatch, duplicateIdentity, overlappingEdits
        case invalidNamespace, markerCollision, oversizedInput, invalidPrefix
        case markerIdentity, markerProvenance, referenceProvenance
    }

    struct Marker: Sendable {
        let id: UUID
        let text: String
        let authoredSource: String
        let generatedRange: NSRange
    }

    public let id = UUID()
    public let source: String
    public let rewritten: String
    let family: String
    let markers: [String: Marker]
    let references: [Reference]

    private struct Edit {
        let range: Range<Int>
        let expectedSource: String
        let replacement: String
        let id: UUID?
    }

    public init(
        source: String, prefix: String = "", replacements: [Replacement], sourceEdits: [SourceEdit] = [],
        references: [Reference] = [],
        namespace: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) throws {
        try Task.checkCancellation()
        let limit = PreviewParserBudget.maximumUTF8Bytes
        guard source.utf8.count <= limit, prefix.utf8.count <= limit,
              replacements.count <= 512, sourceEdits.count <= 1024 - replacements.count
        else { throw Failure.oversizedInput }
        guard prefix.isEmpty || Self.endsInBlankLine(prefix) else { throw Failure.invalidPrefix }
        guard namespace.utf8.count == 32,
              namespace.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) })
        else { throw Failure.invalidNamespace }
        let family = "MTEQ" + namespace + "Z"
        guard !Self.contains(family, in: source), !Self.contains(family, in: prefix)
        else { throw Failure.markerCollision }
        let edits = try Self.edits(replacements: replacements, sourceEdits: sourceEdits, family: family)
        let projectedBytes = try Self.projectedBytes(source: source, prefix: prefix, edits: edits)
        let (rewritten, generated) = try Self.rewrite(source: source, prefix: prefix, edits: edits,
                                                      projectedBytes: projectedBytes)
        self.references = try PreviewMathReferenceProjection.project(
            references, source: source, prefixLength: prefix.utf16.count,
            changes: edits.map { .init(range: $0.range, replacementLength: $0.replacement.utf16.count) }
        )
        self.source = source
        self.rewritten = rewritten
        self.family = family
        markers = generated
    }

    private static func edits(replacements: [Replacement], sourceEdits: [SourceEdit], family: String) throws -> [Edit] {
        var identities = Set<UUID>()
        var edits: [Edit] = []
        for (index, replacement) in replacements.enumerated() {
            try Task.checkCancellation()
            guard identities.insert(replacement.id).inserted else { throw Failure.duplicateIdentity }
            edits.append(Edit(range: replacement.range, expectedSource: replacement.expectedSource,
                              replacement: family + String(index) + "Q", id: replacement.id))
        }
        for edit in sourceEdits {
            try Task.checkCancellation()
            guard edit.replacement.utf8.count <= PreviewParserBudget.maximumUTF8Bytes
            else { throw Failure.oversizedInput }
            guard !Self.contains(family, in: edit.replacement) else { throw Failure.markerCollision }
            edits.append(Edit(range: edit.range, expectedSource: edit.expectedSource,
                              replacement: edit.replacement, id: nil))
        }
        edits.sort { $0.range.lowerBound < $1.range.lowerBound }
        return edits
    }

    private static func projectedBytes(source: String, prefix: String, edits: [Edit]) throws -> Int {
        let original = source as NSString
        var previousEnd = 0
        var projectedBytes = source.utf8.count + prefix.utf8.count
        for edit in edits {
            try Task.checkCancellation()
            guard !edit.range.isEmpty, edit.range.lowerBound >= 0, edit.range.upperBound <= original.length,
                  Self.isBoundary(edit.range.lowerBound, in: original), Self.isBoundary(
                      edit.range.upperBound,
                      in: original
                  )
            else { throw Failure.invalidRange }
            guard edit.range.lowerBound >= previousEnd else { throw Failure.overlappingEdits }
            let actual = original.substring(with: NSRange(location: edit.range.lowerBound, length: edit.range.count))
            guard actual.utf8.elementsEqual(edit.expectedSource.utf8) else { throw Failure.sourceMismatch }
            projectedBytes += edit.replacement.utf8.count - actual.utf8.count
            previousEnd = edit.range.upperBound
        }
        guard projectedBytes <= PreviewParserBudget.maximumUTF8Bytes else { throw Failure.oversizedInput }
        return projectedBytes
    }

    private static func rewrite(source: String, prefix: String, edits: [Edit],
                                projectedBytes: Int) throws -> (String, [String: Marker]) {
        let original = source as NSString
        var rewritten = prefix
        rewritten.reserveCapacity(projectedBytes)
        var generated: [String: Marker] = [:]
        var cursor = 0
        var outputOffset = prefix.utf16.count
        for edit in edits {
            try Task.checkCancellation()
            let untouched = original.substring(with: NSRange(location: cursor, length: edit.range.lowerBound - cursor))
            rewritten += untouched
            outputOffset += untouched.utf16.count
            if let id = edit.id {
                generated[edit.replacement] = Marker(
                    id: id, text: edit.replacement, authoredSource: edit.expectedSource,
                    generatedRange: NSRange(location: outputOffset, length: edit.replacement.utf16.count)
                )
            }
            rewritten += edit.replacement
            outputOffset += edit.replacement.utf16.count
            cursor = edit.range.upperBound
        }
        rewritten += original.substring(from: cursor)
        return (rewritten, generated)
    }

    private static func contains(_ value: String, in source: String) -> Bool {
        (source as NSString).range(of: value, options: .literal).location != NSNotFound
    }

    private static func isBoundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1)
        let current = source.character(at: offset)
        return !(previous == 13 && current == 10) &&
            !((0xD800 ... 0xDBFF).contains(previous) && (0xDC00 ... 0xDFFF).contains(current))
    }

    private static func endsInBlankLine(_ value: String) -> Bool {
        let bytes = value.utf8
        return bytes.suffix(2).elementsEqual([10, 10]) || bytes.suffix(2).elementsEqual([13, 13]) ||
            bytes.suffix(4).elementsEqual([13, 10, 13, 10])
    }
}
