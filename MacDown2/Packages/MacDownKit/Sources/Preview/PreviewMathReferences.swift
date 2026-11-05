import Foundation

public extension PreviewMathInput {
    enum ReferenceKind: Sendable, Equatable { case link, image }

    /// A resolved resource from the original parser facts, in block-local UTF-16.
    /// A replayed definition alone cannot authorize a new link or image.
    struct Reference: Sendable {
        public let range: Range<Int>
        public let destination: String
        public let kind: ReferenceKind

        public init(range: Range<Int>, destination: String, kind: ReferenceKind) {
            self.range = range
            self.destination = destination
            self.kind = kind
        }
    }
}

/// Forward-project only proven original endpoints through the exact edits.
/// Endpoints inside a replacement are ambiguous and cannot acquire authority.
enum PreviewMathReferenceProjection {
    struct Change {
        let range: Range<Int>
        let replacementLength: Int
    }

    static func project(
        _ references: [PreviewMathInput.Reference], source: String, prefixLength: Int, changes: [Change]
    ) throws -> [PreviewMathInput.Reference] {
        guard references.count <= 1024 else { throw PreviewMathInput.Failure.oversizedInput }
        let original = source as NSString
        var bytes = 0
        var deltas = [0]
        var delta = 0
        for change in changes {
            delta += change.replacementLength - change.range.count
            deltas.append(delta)
        }
        func endpoint(_ offset: Int) throws -> Int {
            var low = 0, high = changes.count
            while low < high {
                let middle = low + (high - low) / 2
                if changes[middle].range.upperBound <= offset {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            guard low == changes.count || offset <= changes[low].range.lowerBound else {
                throw PreviewMathInput.Failure.invalidRange
            }
            return prefixLength + offset + deltas[low]
        }
        var projected: [PreviewMathInput.Reference] = []
        for reference in references {
            try Task.checkCancellation()
            let range = reference.range
            guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= original.length,
                  boundary(range.lowerBound, in: original), boundary(range.upperBound, in: original)
            else { throw PreviewMathInput.Failure.invalidRange }
            let size = reference.destination.utf8.count
            guard size <= PreviewParserBudget.maximumUTF8Bytes - bytes else {
                throw PreviewMathInput.Failure.oversizedInput
            }
            bytes += size
            try projected.append(.init(range: endpoint(range.lowerBound) ..< endpoint(range.upperBound),
                                       destination: reference.destination, kind: reference.kind))
        }
        return projected.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func boundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1), current = source.character(at: offset)
        return !(previous == 13 && current == 10) &&
            !((0xD800 ... 0xDBFF).contains(previous) && (0xDC00 ... 0xDFFF).contains(current))
    }
}

/// Same-role ranges from an ordinary parse cannot overlap. Fail closed for
/// fabricated or structurally ambiguous input rather than choosing a target.
struct PreviewMathReferenceIndex {
    let references: [PreviewMathInput.Reference]
    let isValid: Bool

    init(_ references: [PreviewMathInput.Reference], kind: PreviewMathInput.ReferenceKind) {
        self.references = references.filter { $0.kind == kind }
        isValid = zip(self.references, self.references.dropFirst())
            .allSatisfy { $0.range.upperBound <= $1.range.lowerBound }
    }

    func authorizes(_ url: URL, range: NSRange, baseURL: URL?) -> Bool {
        matchingReference(url, range: range, baseURL: baseURL) != nil
    }

    func matchingReference(_ url: URL, range: NSRange, baseURL: URL?) -> Int? {
        guard isValid, range.location >= 0, range.length > 0,
              range.location <= Int.max - range.length else { return nil }
        var low = 0, high = references.count
        while low < high {
            let middle = low + (high - low) / 2
            if references[middle].range.lowerBound <= range.location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return nil }
        let reference = references[low - 1]
        guard NSMaxRange(range) <= reference.range.upperBound,
              let expected = URL(string: reference.destination, relativeTo: baseURL),
              url.absoluteString.utf8.elementsEqual(expected.absoluteString.utf8) else { return nil }
        return low - 1
    }
}
