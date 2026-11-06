import CryptoKit
import Foundation
import SwiftSoup

/// Checks the HTML the pinned cmark renderer actually emitted. This opt-in
/// analysis never serializes SwiftSoup's repaired DOM back into the export:
/// authored HTML bytes are preserved, and ambiguous targets fail closed.
enum EmittedHeadingDOM {
    static let maximumAnalyzedBytes = 8 * 1024 * 1024
    static let maximumExplicitIDs = 4096

    struct Inspection: Sendable {
        let markedHTMLSHA256: String
        let reservedIDs: [String]
        let elementTags: [String]
        let markerParentIndex: [String: Int]
    }

    /// First pass: prove every private cmark marker is a direct child of the
    /// expected generated heading and inventory the exact emitted DOM IDs.
    /// Call only on a worker; parser objects never escape the serial lock.
    static func inspect(
        _ rendered: CMarkGFM.Rendered, generatedNamespaceFamily: String? = nil,
        svgRoots: [HeadingSVGNamespace.Root] = []
    ) -> Inspection? {
        guard !rendered.headingMarkers.isEmpty,
              rendered.html.utf8.count <= maximumAnalyzedBytes else { return nil }
        let markers = rendered.headingMarkers
        guard Set(markers.map(\.comment)).count == markers.count,
              markers.allSatisfy({ $0.comment.hasPrefix("<!--MT117-") && $0.comment.hasSuffix("-->") })
        else { return nil }
        let expectedByData = Dictionary(uniqueKeysWithValues: markers.map {
            (String($0.comment.dropFirst(4).dropLast(3)), $0.location.level)
        })

        return parserLock.withLock {
            guard let document = try? SwiftSoup.parseBodyFragment(rendered.html),
                  let elements = try? document.getAllElements().array(),
                  HeadingSVGNamespace.validate(elements: elements, family: generatedNamespaceFamily, roots: svgRoots)
            else { return nil }
            return inspectElements(
                elements, expectedByData: expectedByData,
                expectedCount: markers.count, markedHTML: rendered.html,
                generatedNamespaceFamily: generatedNamespaceFamily
            )
        }
    }

    /// Patch only the unique `<hN><private-comment>` sequences proven by the
    /// first pass, then parse the actual output to ensure each new fragment
    /// names exactly that heading and no authored ID or named anchor.
    static func publish(
        inspected: Inspection,
        rendered: CMarkGFM.Rendered,
        matches: [EmittedHeadingMatcher.Match]
    ) -> String? {
        guard inspected.markedHTMLSHA256 == sha256(rendered.html),
              matches.count == rendered.headingMarkers.count else { return nil }
        let fragments = matches.map(\.indexed.fragment)
        let fragmentKeys = fragments.map { Data($0.utf8) }
        let reservedKeys = Set(inspected.reservedIDs.map { Data($0.utf8) })
        guard Set(fragmentKeys).count == fragments.count,
              fragmentKeys.allSatisfy({ !reservedKeys.contains($0) }) else { return nil }

        var replacements: [String: (level: Int, fragment: String)] = [:]
        for (match, marker) in zip(matches, rendered.headingMarkers) {
            guard match.emitted == marker.location else { return nil }
            replacements[marker.comment] = (marker.location.level, match.indexed.fragment)
        }
        guard replacements.count == matches.count,
              let patched = patchMarkedHeadings(rendered.html, replacements: replacements) else { return nil }
        guard patched.utf8.count <= maximumAnalyzedBytes else { return nil }

        return parserLock.withLock {
            guard let document = try? SwiftSoup.parseBodyFragment(patched),
                  let elements = try? document.getAllElements().array(),
                  validateFinalElements(
                      elements, inspected: inspected, matches: matches,
                      markers: rendered.headingMarkers
                  ) else { return nil }
            return patched
        }
    }

    private static let parserLock = NSLock()

    private static func inspectElements(
        _ elements: [Element], expectedByData: [String: Int],
        expectedCount: Int, markedHTML: String, generatedNamespaceFamily: String?
    ) -> Inspection? {
        var reservedIDs: [String] = []
        var namespaceIDs: Set<Data> = []
        var explicitCount = 0
        var markerParents: [String: Int] = [:]
        var tags: [String] = []
        tags.reserveCapacity(elements.count)
        for (position, element) in elements.enumerated() {
            let tag = element.tagNameNormal()
            tags.append(tag)
            if element.hasAttr("id"), let value = try? element.attr("id") {
                let namespaced = value.utf8.starts(with: "mt117-svg-".utf8) ||
                    generatedNamespaceFamily.map { value.utf8.starts(with: $0.utf8) } == true
                if namespaced, !namespaceIDs.insert(Data(value.utf8)).inserted {
                    return nil
                }
                reservedIDs.append(value)
                explicitCount += 1
            }
            if tag == "a", element.hasAttr("name"), let value = try? element.attr("name") {
                if let family = generatedNamespaceFamily, value.utf8.starts(with: family.utf8),
                   !namespaceIDs.insert(Data(value.utf8)).inserted {
                    return nil
                }
                reservedIDs.append(value)
                explicitCount += 1
            }
            guard explicitCount <= maximumExplicitIDs else { return nil }
            for case let comment as Comment in element.childNodesCopy() {
                let data = comment.getData()
                guard let level = expectedByData[data] else { continue }
                guard tag == "h\(level)", markerParents.updateValue(position, forKey: data) == nil else {
                    return nil
                }
            }
        }
        guard markerParents.count == expectedCount else { return nil }
        return Inspection(
            markedHTMLSHA256: sha256(markedHTML), reservedIDs: reservedIDs,
            elementTags: tags, markerParentIndex: markerParents
        )
    }

    private static func validateFinalElements(
        _ elements: [Element], inspected: Inspection,
        matches: [EmittedHeadingMatcher.Match], markers: [CMarkGFM.HeadingMarker]
    ) -> Bool {
        guard elements.map({ $0.tagNameNormal() }) == inspected.elementTags else { return false }
        var targetPositions: [Data: [Int]] = [:]
        let targetSet = Set(matches.map { Data($0.indexed.fragment.utf8) })
        for (position, element) in elements.enumerated() {
            if element.hasAttr("id"), let value = try? element.attr("id"), targetSet.contains(Data(value.utf8)) {
                targetPositions[Data(value.utf8), default: []].append(position)
            }
            if element.tagNameNormal() == "a", element.hasAttr("name"),
               let value = try? element.attr("name"), targetSet.contains(Data(value.utf8)) {
                targetPositions[Data(value.utf8), default: []].append(position)
            }
        }
        for (match, marker) in zip(matches, markers) {
            let data = String(marker.comment.dropFirst(4).dropLast(3))
            guard let expected = inspected.markerParentIndex[data], expected < elements.count,
                  targetPositions[Data(match.indexed.fragment.utf8)] == [expected],
                  elements[expected].tagNameNormal() == "h\(marker.location.level)" else { return false }
        }
        return true
    }

    static func patchMarkedHeadings(
        _ html: String,
        replacements: [String: (level: Int, fragment: String)]
    ) -> String? {
        guard let pattern = try? NSRegularExpression(pattern: "<!--MT117-[0-9A-Fa-f-]+-[0-9]+-->")
        else { return nil }
        let source = html as NSString
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: source.length))
        var seen: Set<String> = []
        var patches: [(NSRange, String)] = []
        for match in matches {
            let comment = source.substring(with: match.range)
            guard let replacement = replacements[comment] else { continue }
            let prefix = "<h\(replacement.level)>"
            guard seen.insert(comment).inserted, match.range.location >= prefix.utf16.count else { return nil }
            let range = NSRange(
                location: match.range.location - prefix.utf16.count,
                length: prefix.utf16.count + match.range.length
            )
            guard source.substring(with: NSRange(location: range.location, length: prefix.utf16.count))
                == prefix else { return nil }
            let newTag = "<h\(replacement.level) id=\"\(HTMLEscaping.escape(replacement.fragment))\">"
            patches.append((range, newTag))
        }
        guard seen.count == replacements.count else { return nil }
        // Advance through UTF-16 once. Repeated insertion into a mutable body
        // shifts the entire remaining tail per heading on large pure documents.
        var output = ""
        output.reserveCapacity(html.utf8.count)
        var cursor = html.utf16.startIndex
        var consumed = 0
        for (range, replacement) in patches {
            let start = html.utf16.index(cursor, offsetBy: range.location - consumed)
            let end = html.utf16.index(start, offsetBy: range.length)
            output.append(contentsOf: html[cursor ..< start])
            output.append(replacement)
            cursor = end
            consumed = range.location + range.length
        }
        output.append(contentsOf: html[cursor...])
        return output
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
