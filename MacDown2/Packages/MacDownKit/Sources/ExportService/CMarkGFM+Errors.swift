import Foundation

extension CMarkGFM {
    enum CMarkError: Error, LocalizedError, CustomStringConvertible {
        case parserCreationFailed
        case parseProducedNoDocument
        case renderFailed

        var description: String {
            switch self {
            case .parserCreationFailed: "cmark could not create a parser"
            case .parseProducedNoDocument: "cmark produced no document"
            case .renderFailed: "cmark could not render HTML"
            }
        }

        var errorDescription: String? {
            switch self {
            case .parserCreationFailed: String(localized: "cmark could not create a parser", bundle: .module)
            case .parseProducedNoDocument: String(localized: "cmark produced no document", bundle: .module)
            case .renderFailed: String(localized: "cmark could not render HTML", bundle: .module)
            }
        }
    }

    /// Replaces each deferred inline sentinel in the rendered HTML in ONE pass (a `replacingOccurrences` per
    /// contribution over the whole document was quadratic: 1000 table cells took 13 s).
    ///
    /// Only the FIRST occurrence of each sentinel, and only in text content (outside any `<…>` tag), is replaced. The
    /// sentinel can also appear in an attribute value — authored text such as a link title written with an entity
    /// (`E12INLIN&#69;0Z`) or a backslash escape is decoded by cmark into the exact sentinel — and pasting derived
    /// markup there produced `title="<img src=…>"` with no diagnostic and bypassed the leak check. Anything left over
    /// is
    /// then seen by `leakedSentinelIndices`, which re-composes without that contribution.
    static func substitutingDeferredSentinels(_ specs: [CustomNodeSpec], in html: String) -> String {
        guard !specs.isEmpty,
              let expression = try? NSRegularExpression(pattern: "E12INLINE_*[0-9]+Z") else { return html }
        let bySentinel = Dictionary(specs.map { ($0.sentinel, $0.html) }, uniquingKeysWith: { first, _ in first })
        let source = html as NSString
        var output = ""
        var cursor = 0
        var scanned = 0
        var insideTag = false
        var used: Set<String> = []
        for match in expression.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            while scanned < match.range.location {
                switch source.character(at: scanned) {
                case 0x3C: insideTag = true // `<`
                case 0x3E: insideTag = false // `>`
                default: break
                }
                scanned += 1
            }
            let sentinel = source.substring(with: match.range)
            guard !insideTag, let replacement = bySentinel[sentinel], used.insert(sentinel).inserted else { continue }
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += replacement
            cursor = match.range.location + match.range.length
        }
        return output + source.substring(from: cursor)
    }
}
