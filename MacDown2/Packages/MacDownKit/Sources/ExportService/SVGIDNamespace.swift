import Foundation
import SwiftSoup

/// Gives each accepted diagram occurrence its own SVG IDs. Renderer caches keep
/// their canonical artwork; this runs only on the sanitized export fragment.
/// Unsupported SVG/CSS syntax fails closed so a partial rewrite cannot leave
/// references pointing at a different diagram or an authored element.
enum SVGIDNamespace {
    static func rewrite(_ html: String, occurrence: Int, family: String = "mt117-svg-") -> String? {
        guard validID(family), family.hasSuffix("-"), family.utf8.count <= 64 else { return nil }
        guard html.lowercased().contains("<svg") else { return html }
        let scalars = Array(html.unicodeScalars)
        guard let roots = findRoots(in: scalars), !roots.isEmpty else { return nil }
        var output = ""
        var copiedThrough = 0
        for (ordinal, root) in roots.enumerated() {
            output += String(String.UnicodeScalarView(scalars[copiedThrough ..< root.lowerBound]))
            let fragment = String(String.UnicodeScalarView(scalars[root]))
            guard let rewritten = rewriteRoot(fragment, prefix: "\(family)\(occurrence)-\(ordinal)-")
            else { return nil }
            output += rewritten
            copiedThrough = root.upperBound
        }
        output += String(String.UnicodeScalarView(scalars[copiedThrough...]))
        return output
    }

    static func findRoots(in scalars: [Unicode.Scalar]) -> [Range<Int>]? {
        var roots: [Range<Int>] = []
        var cursor = 0
        var rootStart: Int?
        var depth = 0
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else { cursor += 1; continue }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
            if tag.name == "svg" {
                if !tag.isClosing {
                    guard !tag.isSelfClosing else { return nil }
                    if depth == 0 {
                        rootStart = cursor
                    }
                    depth += 1
                } else {
                    guard depth > 0 else { return nil }
                    depth -= 1
                    if depth == 0 {
                        guard let start = rootStart else { return nil }
                        roots.append(start ..< tag.end)
                        rootStart = nil
                    }
                }
            }
            cursor = tag.end
        }
        return depth == 0 ? roots : nil
    }

    static func rewriteRoot(_ svg: String, prefix: String, additionalReferenceIDs: Set<String> = []) -> String? {
        let scalars = Array(svg.unicodeScalars)
        guard let ids = collectIDs(in: scalars),
              let root = HTMLTagScanner.parseTag(at: 0, in: scalars), root.name == "svg" else { return nil }
        let authoredRootID = root.attributes.first { $0.name == "id" }?.value
            .flatMap { try? Parser.unescapeEntities($0, true) }
        let rootClasses = Set((root.attributes.first { $0.name == "class" }?.value
                .flatMap { try? Parser.unescapeEntities($0, true) } ?? "")
            .split(whereSeparator: \.isWhitespace).map(String.init))
        let scopeID: String
        if let authoredRootID {
            scopeID = prefix + authoredRootID
        } else {
            // The browser sees decoded attribute references. Reserving only
            // against raw bytes can make an unresolved entity-encoded paint
            // URL resolve to the synthetic root we just created.
            guard let decoded = try? Parser.unescapeEntities(svg, true) else { return nil }
            var synthetic = "mtScope"
            while svg.contains(synthetic) || decoded.contains(synthetic), synthetic.count < 64 {
                synthetic += "_"
            }
            guard !svg.contains(synthetic), !decoded.contains(synthetic) else { return nil }
            scopeID = prefix + synthetic
        }
        guard additionalReferenceIDs.allSatisfy(validID) else { return nil }
        return rewriteTags(in: scalars, ids: ids.union(additionalReferenceIDs), prefix: prefix,
                           scope: (scopeID, authoredRootID == nil), rootClasses: rootClasses)
    }

    static func collectIDs(in scalars: [Unicode.Scalar]) -> Set<String>? {
        var ids: Set<String> = []
        var cursor = 0
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else { cursor += 1; continue }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
            if !tag.isClosing {
                for attribute in tag.attributes where attribute.name == "id" {
                    guard let raw = attribute.value, let value = try? Parser.unescapeEntities(raw, true),
                          validID(value), ids.insert(value).inserted else { return nil }
                }
            }
            cursor = tag.end
        }
        return ids
    }

    private static func rewriteTags(
        in scalars: [Unicode.Scalar], ids: Set<String>, prefix: String,
        scope: (id: String, addRootID: Bool), rootClasses: Set<String>
    ) -> String? {
        let (scopeID, addRootID) = scope
        guard let hasFontFace = admittedFontFaceScope(in: scalars) else { return nil }
        var output = ""
        var cursor = 0
        var style = false
        var rootOpened = false
        while cursor < scalars.count {
            guard scalars[cursor] == "<" else {
                let start = cursor
                while cursor < scalars.count, scalars[cursor] != "<" {
                    cursor += 1
                }
                let text = String(String.UnicodeScalarView(scalars[start ..< cursor]))
                if style {
                    guard let rewritten = rewriteStyle(
                        text, ids: ids, prefix: prefix, scopeID: scopeID, rootClasses: rootClasses
                    )
                    else { return nil }
                    output += rewritten
                } else {
                    output += text
                }
                continue
            }
            guard let tag = HTMLTagScanner.parseTag(at: cursor, in: scalars) else { return nil }
            if tag.name == "style" {
                style = !tag.isClosing
            }
            if tag.isClosing {
                output += "</\(tag.name)>"
            } else {
                guard let opening = openingTag(tag, ids: ids, prefix: prefix, hasFontFace: hasFontFace)
                else { return nil }
                output += scopedOpening(opening, isFirstRoot: tag.name == "svg" && !rootOpened,
                                        scopeID: scopeID, addRootID: addRootID)
                rootOpened = rootOpened || tag.name == "svg"
            }
            cursor = tag.end
        }
        return style ? nil : output
    }

    private static func scopedOpening(
        _ opening: String, isFirstRoot: Bool, scopeID: String, addRootID: Bool
    ) -> String {
        guard isFirstRoot, addRootID else { return opening }
        return String(opening.dropLast()) + " id=\"\(scopeID)\">"
    }

    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39)
                || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x61 && $0.value <= 0x7A)
                || $0 == "-" || $0 == "_"
        }
    }

    private static func openingTag(
        _ tag: HTMLTagScanner.Tag, ids: Set<String>, prefix: String, hasFontFace: Bool
    ) -> String? {
        var output = "<\(tag.name)"
        for attribute in tag.attributes {
            guard let raw = attribute.value else {
                guard !resourceLoadingAttributes.contains(attribute.name) else { return nil }
                output += " \(attribute.name)"
                continue
            }
            guard let value = try? Parser.unescapeEntities(raw, true) else { return nil }
            if hasFontFace {
                let compact = value.lowercased().filter { !$0.isWhitespace }
                if attribute.name == "font-family" || attribute.name == "font"
                    || (attribute.name == "style"
                        && (compact.contains("font-family:") || compact.contains("font:"))) {
                    return nil
                }
            }
            guard let updated = rewrittenValue(value, attribute: attribute.name, tagName: tag.name,
                                               ids: ids, prefix: prefix) else { return nil }
            let emitted = updated == value ? raw : HTMLEscaping.escape(updated)
            output += " \(attribute.name)=\"\(emitted)\""
        }
        return output + (tag.isSelfClosing ? " />" : ">")
    }

    private static func rewrittenValue(
        _ value: String, attribute: String, tagName: String, ids: Set<String>, prefix: String
    ) -> String? {
        var updated = value
        switch attribute {
        case "id": updated = prefix + value
        case "href", "xlink:href":
            guard let href = rewrittenHref(value, tagName: tagName, ids: ids, prefix: prefix) else { return nil }
            updated = href
        case "src", "srcset", "imagesrcset", "poster", "background": return nil
        case "aria-labelledby", "aria-describedby", "aria-controls", "aria-owns", "aria-flowto", "aria-details":
            let targets = value.split(whereSeparator: \.isWhitespace)
            guard targets.allSatisfy({ validID(String($0)) && ids.contains(String($0)) }) else { return nil }
            updated = targets.map { prefix + $0 }.joined(separator: " ")
        default: break
        }
        if attribute == "style" {
            return rewriteInlineStyle(updated, ids: ids, prefix: prefix)
        }
        if urlBearingAttributes.contains(attribute) {
            return rewrittenResourceValue(updated, ids: ids, prefix: prefix)
        }
        return updated
    }

    private static func rewrittenResourceValue(_ value: String, ids: Set<String>, prefix: String) -> String? {
        guard safeResourceURLs(in: value) else { return nil }
        return rewriteURLReferences(value, ids: ids, prefix: prefix)
    }

    private static func rewrittenHref(_ value: String, tagName: String, ids: Set<String>, prefix: String) -> String? {
        let target = String(value.dropFirst())
        if tagName != "a" {
            // SVG image/use/text-path links can load without a user click.
            // The sanitizer permits HTTPS for interactive links, so require
            // an owned local target on every other element.
            guard value.first == "#", ids.contains(target) else { return nil }
            return "#" + prefix + target
        }
        if value.first == "#" {
            guard validID(target), ids.contains(target) else { return nil }
            return "#" + prefix + target
        }
        return value
    }

    static func rewriteURLReferences(_ text: String, ids: Set<String>, prefix: String) -> String? {
        var output = ""
        var cursor = text.startIndex
        while let opening = text.range(of: "url(", options: .caseInsensitive, range: cursor ..< text.endIndex) {
            guard let close = text[opening.upperBound...].firstIndex(of: ")") else { return nil }
            let raw = text[opening.upperBound ..< close]
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let quote = value.first, quote == "\"" || quote == "'" {
                guard value.count >= 2, value.last == quote else { return nil }
                value.removeFirst()
                value.removeLast()
            }
            if value.lowercased().hasPrefix("data:") {
                // Embedded WOFF URLs have already passed safeResourceURLs.
                output += text[cursor ... close]
                cursor = text.index(after: close)
                continue
            }
            guard value.first == "#", validID(String(value.dropFirst())),
                  ids.contains(String(value.dropFirst())), let hash = raw.firstIndex(of: "#")
            else { return nil }
            let idStart = text.index(after: hash)
            output += text[cursor ..< idStart]
            output += prefix + value.dropFirst()
            cursor = text.index(idStart, offsetBy: value.dropFirst().count)
        }
        output += text[cursor...]
        return output
    }

    private static let urlBearingAttributes: Set<String> = [
        "clip-path", "color-profile", "cursor", "fill", "filter", "marker", "marker-start",
        "marker-mid", "marker-end", "mask", "stroke", "style",
    ]

    private static let resourceLoadingAttributes: Set<String> = [
        "href", "xlink:href", "src", "srcset", "imagesrcset", "poster", "background",
    ]
}
