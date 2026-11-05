import Foundation
import Math

/// Limits retained output before base64/escaped HTML construction, independently
/// of ExportService's later complete-document and resource publication gates.
struct MathExportFragmentBudget: Sendable {
    struct Exhausted: Error {}

    let maximumPNGBytes: Int
    let maximumHTMLBytes: Int
    private(set) var pngBytes = 0
    private(set) var htmlBytes = 0

    static let standard = MathExportFragmentBudget(maximumPNGBytes: 16 << 20, maximumHTMLBytes: 24 << 20)

    var remainingHTMLBytes: Int {
        max(0, maximumHTMLBytes - htmlBytes)
    }

    /// Checked integer arithmetic also handles deliberately hostile test limits.
    mutating func admit(png: Int, html: Int) throws {
        guard maximumPNGBytes >= 0, maximumHTMLBytes >= 0, png >= 0, html >= 0,
              png <= maximumPNGBytes - pngBytes, html <= maximumHTMLBytes - htmlBytes else { throw Exhausted() }
        pngBytes += png
        htmlBytes += html
    }
}

/// Fixed markup, exact scalar escaping and admission before output allocation.
struct MathExportFragmentBuilder {
    private(set) var budget: MathExportFragmentBudget

    init(budget: MathExportFragmentBudget = .standard) {
        self.budget = budget
    }

    mutating func image(_ image: RenderedMathImage, alt: String) throws -> String {
        try Task.checkCancellation()
        try MathImageBudget.standard.validatePNGByteCount(image.pngData.count)
        _ = try MathImageBudget.standard.admit(logicalWidth: image.logicalWidth,
                                               logicalHeight: image.logicalHeight, pixelScale: 1)
        let width = image.logicalWidth.rounded(), height = image.logicalHeight.rounded()
        guard width > 0, height > 0 else { throw MathRenderError.invalidImageDimensions }
        let prefix = "<img src=\"data:image/png;base64,"
        let middle = "\" width=\"\(Int(width))\" height=\"\(Int(height))\" alt=\""
        let suffix = "\">"
        let base64Bytes = ((image.pngData.count + 2) / 3) * 4
        let fixed = prefix.utf8.count + middle.utf8.count + suffix.utf8.count
        guard fixed <= budget.remainingHTMLBytes, base64Bytes <= budget.remainingHTMLBytes - fixed else {
            throw MathExportFragmentBudget.Exhausted()
        }
        let escapedBytes = try Self.escapedSize(
            alt.unicodeScalars,
            maximum: budget.remainingHTMLBytes - fixed - base64Bytes
        )
        try budget.admit(png: image.pngData.count, html: fixed + base64Bytes + escapedBytes)
        try Task.checkCancellation()
        return prefix + image.pngData.base64EncodedString() + middle + Self.escaped(
            alt.unicodeScalars,
            bytes: escapedBytes
        ) + suffix
    }

    /// Slice a proven scalar-safe original range without making a substring copy.
    /// Source parsing already established the range; validate the public boundary again.
    mutating func literal(source: String, range: Range<Int>) throws -> String {
        try Task.checkCancellation()
        let original = source as NSString
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= original.length,
              Self.boundary(range.lowerBound, in: original), Self.boundary(range.upperBound, in: original) else {
            throw MathRenderError.invalidImageDimensions
        }
        let prefix = "<code class=\"math-source-fallback\" style=\"white-space:pre-wrap\">"
        let suffix = "</code>"
        let fixed = prefix.utf8.count + suffix.utf8.count
        guard fixed <= budget.remainingHTMLBytes, range.count <= budget.remainingHTMLBytes - fixed else {
            throw MathExportFragmentBudget.Exhausted()
        }
        let lower = String.Index(utf16Offset: range.lowerBound, in: source)
        let upper = String.Index(utf16Offset: range.upperBound, in: source)
        let scalars = source.unicodeScalars[lower ..< upper]
        let size = try Self.escapedSize(scalars, maximum: budget.remainingHTMLBytes - fixed)
        try budget.admit(png: 0, html: fixed + size)
        try Task.checkCancellation()
        return prefix + Self.escaped(scalars, bytes: size) + suffix
    }

    private static func escapedSize(_ scalars: some Collection<Unicode.Scalar>, maximum: Int) throws -> Int {
        var bytes = 0
        var steps = 0
        for scalar in scalars {
            if steps % 4096 == 0 {
                try Task.checkCancellation()
            }
            steps += 1
            let size = replacement(scalar)?.utf8.count ?? scalar.utf8.count
            guard size <= maximum - bytes else { throw MathExportFragmentBudget.Exhausted() }
            bytes += size
        }
        return bytes
    }

    private static func escaped(_ scalars: some Collection<Unicode.Scalar>, bytes: Int) -> String {
        var result = ""
        result.reserveCapacity(bytes)
        for scalar in scalars {
            if let replacement = replacement(scalar) {
                result += replacement
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func replacement(_ scalar: Unicode.Scalar) -> String? {
        switch scalar {
        case "&": "&amp;"
        case "\"": "&quot;"
        case "'": "&#39;"
        case "<": "&lt;"
        case ">": "&gt;"
        default: nil
        }
    }

    private static func boundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        let previous = source.character(at: offset - 1), current = source.character(at: offset)
        return !(previous == 13 && current == 10) &&
            !((0xD800 ... 0xDBFF).contains(previous) && (0xDC00 ... 0xDFFF).contains(current))
    }
}
