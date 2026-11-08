import CryptoKit
import Foundation
import SwiftSoup
import Themes

/// Private acceptance boundary for opt-in SVG contributions. The ordinary
/// export writers never call this path. A receipt covers one exact assembled
/// document and cannot be reused after body, head or template recomposition.
enum SVGAssemblyOwnership {
    /// The opt-in path may accept only the exact stylesheet generated from a
    /// bundled, reviewed structural sheet and colour-only theme variables.
    /// A raw authored style cannot manufacture this value by passing CSS bytes.
    struct AuditedHeadCSS: Sendable, Equatable {
        let stylesheet: String

        /// ExportHTMLWriter.embeddedStyleElement wraps its stylesheet with
        /// these exact newlines. Compare DOM style data to emitted bytes.
        var emittedStyleData: String {
            "\n" + stylesheet + "\n"
        }

        static func builtIn(for theme: Theme, target: ExportTarget? = nil) -> Self? {
            let structural = ExportComposer.structuralStylesheet(for: target)
            guard ExportThemeStylesheet.hasClosedReferences(structuralCSS: structural)
            else { return nil }
            return Self(stylesheet: ExportThemeStylesheet.variables(for: theme) + "\n" + structural)
        }
    }

    struct Manifest: Sendable {
        fileprivate let markedSHA256: String
        fileprivate let fragmentSHA256: String
        fileprivate let fragmentRoots: [SVGIDNamespace.MarkedRoot]
        fileprivate let auditedHeadCSS: AuditedHeadCSS?
        fileprivate let requiredCSP: String?
        fileprivate let roots: [RootInspection]
    }

    struct Publication: Sendable {
        let html: String
        fileprivate let sha256: String
    }

    fileprivate struct RootInspection: Sendable, Equatable {
        let rootID: String
        let ownedIDs: Set<String>
        let references: Set<String>
        let keyframes: Set<String>
        let fontFamilies: Set<String>
        let ancestorTags: [String]
        let elementIndex: Int
        let subtreeTags: [String]
    }

    private static let parserLock = NSLock()
    private static let maximumAnalyzedBytes = 8 * 1024 * 1024
    private static let maximumRoots = 64
    private static let maximumOwnedIDs = 4096

    static func inspect(
        markedDocument: String, fragment: SVGIDNamespace.MarkedFragment,
        auditedHeadCSS: AuditedHeadCSS? = nil, requiredCSP: String? = nil
    ) -> Manifest? {
        guard markedDocument.utf8.count <= maximumAnalyzedBytes,
              !fragment.roots.isEmpty, fragment.roots.count <= maximumRoots,
              markedDocument.components(separatedBy: fragment.html).count == 2,
              fragment.roots.allSatisfy({
                  markedDocument.components(separatedBy: $0.startMarker).count == 2
                      && markedDocument.components(separatedBy: $0.endMarker).count == 2
              })
        else { return nil }
        return parserLock.withLock {
            guard let document = try? SwiftSoup.parse(markedDocument),
                  let roots = inspect(document, expected: fragment.roots,
                                      markersRequired: true, auditedHeadCSS: auditedHeadCSS,
                                      requiredCSP: requiredCSP),
                  let rawAncestors = rawAncestorMap(
                      for: fragment.roots.map(\.startMarker), in: markedDocument
                  )
            else { return nil }
            for (item, root) in zip(fragment.roots, roots) {
                guard let raw = rawAncestors[item.startMarker],
                      raw == root.ancestorTags.reversed().filter({ $0 != "#root" })
                else { return nil }
            }
            return Manifest(markedSHA256: sha256(markedDocument),
                            fragmentSHA256: sha256(fragment.html),
                            fragmentRoots: fragment.roots,
                            auditedHeadCSS: auditedHeadCSS, requiredCSP: requiredCSP, roots: roots)
        }
    }

    /// Only these returned bytes may be published. Parse again after removing
    /// the private markers; browser repair or changed definitions invalidate
    /// the receipt rather than silently changing the accepted ownership graph.
    static func publish(
        markedDocument: String, fragment: SVGIDNamespace.MarkedFragment,
        inspected: Manifest
    ) -> Publication? {
        guard inspected.markedSHA256 == sha256(markedDocument),
              inspected.fragmentSHA256 == sha256(fragment.html),
              inspected.fragmentRoots == fragment.roots else { return nil }
        guard let publishable = strippedMarkers(from: markedDocument, roots: fragment.roots) else { return nil }
        guard publishable.utf8.count <= maximumAnalyzedBytes else { return nil }
        return parserLock.withLock {
            guard let document = try? SwiftSoup.parse(publishable),
                  let roots = inspect(document, expected: fragment.roots,
                                      markersRequired: false, auditedHeadCSS: inspected.auditedHeadCSS,
                                      requiredCSP: inspected.requiredCSP),
                  roots == inspected.roots else { return nil }
            return Publication(html: publishable, sha256: sha256(publishable))
        }
    }

    static func stillMatches(_ html: String, publication: Publication) -> Bool {
        publication.sha256 == sha256(html)
    }

    /// A rejected diagram's authored fence may be published only after a fresh
    /// composition with no generated roots and the same fixed head policy.
    static func publishFallback(
        _ html: String, auditedHeadCSS: AuditedHeadCSS, requiredCSP: String
    ) -> Publication? {
        guard html.utf8.count <= maximumAnalyzedBytes else { return nil }
        return parserLock.withLock {
            guard let document = try? SwiftSoup.parse(html),
                  inspect(document, expected: [], markersRequired: false,
                          auditedHeadCSS: auditedHeadCSS, requiredCSP: requiredCSP) != nil
            else { return nil }
            return Publication(html: html, sha256: sha256(html))
        }
    }

    private static func strippedMarkers(
        from marked: String, roots: [SVGIDNamespace.MarkedRoot]
    ) -> String? {
        var output = ""
        var cursor = marked.startIndex
        for root in roots {
            for marker in [root.startMarker, root.endMarker] {
                guard let range = marked.range(of: marker, range: cursor ..< marked.endIndex),
                      marked[range.upperBound...].range(of: marker) == nil else { return nil }
                output += marked[cursor ..< range.lowerBound]
                cursor = range.upperBound
            }
        }
        output += marked[cursor...]
        return output
    }

    private static func inspect(
        _ document: Document, expected: [SVGIDNamespace.MarkedRoot],
        markersRequired: Bool, auditedHeadCSS: AuditedHeadCSS?, requiredCSP: String?
    ) -> [RootInspection]? {
        guard let elements = try? document.getAllElements().array() else { return nil }
        let expectedIDs = expected.reduce(into: Set<String>()) { $0.formUnion($1.ownedIDs) }
        guard expectedIDs.count <= maximumOwnedIDs,
              expectedIDs.count == expected.reduce(0, { $0 + $1.ownedIDs.count }) else { return nil }
        var globalIDs: [String: [Element]] = [:]
        for element in elements where element.hasAttr("id") {
            guard let id = try? element.attr("id") else { return nil }
            if id.hasPrefix("mt117-svg-") {
                guard expectedIDs.contains(id) else { return nil }
                globalIDs[id, default: []].append(element)
            }
        }
        guard expectedIDs.allSatisfy({ globalIDs[$0]?.count == 1 }) else { return nil }

        var inspections: [RootInspection] = []
        var rootElements: [Element] = []
        for item in expected {
            guard let root = globalIDs[item.rootID]?.first,
                  let inspection = inspectRoot(root, expected: item, markersRequired: markersRequired)
            else { return nil }
            inspections.append(inspection)
            rootElements.append(root)
        }
        guard validateOutside(elements: elements, roots: rootElements,
                              generatedIDs: expectedIDs, auditedHeadCSS: auditedHeadCSS,
                              requiredCSP: requiredCSP) else { return nil }
        return inspections
    }

    private static func inspectRoot(
        _ root: Element, expected: SVGIDNamespace.MarkedRoot, markersRequired: Bool
    ) -> RootInspection? {
        guard root.tagNameNormal() == "svg", let parent = root.parent(),
              let subtree = try? root.getAllElements().array(),
              let location = parent.children().array().firstIndex(where: { $0 === root })
        else { return nil }
        let ids = subtree.compactMap { element -> String? in
            guard element.hasAttr("id") else { return nil }
            return try? element.attr("id")
        }
        guard ids.count == expected.ownedIDs.count, Set(ids) == expected.ownedIDs,
              markerPairIsValid(around: root, in: parent, item: expected, required: markersRequired),
              let refs = referenceTargets(in: subtree), refs.isSubset(of: expected.ownedIDs),
              let definitions = definitions(in: subtree)
        else { return nil }
        var ancestors: [String] = []
        var cursor: Element? = parent
        while let node = cursor {
            ancestors.append(node.tagNameNormal())
            cursor = node.parent()
        }
        // SVG presentation properties inherit across nested SVG boundaries.
        // An authored outer SVG can supply fill=url(#outside) even when every
        // explicit reference inside this generated subtree is owned.
        guard !ancestors.contains("svg") else { return nil }
        return RootInspection(
            rootID: expected.rootID, ownedIDs: expected.ownedIDs, references: refs,
            keyframes: definitions.keyframes, fontFamilies: definitions.fontFamilies,
            ancestorTags: ancestors, elementIndex: location,
            subtreeTags: subtree.map { $0.tagNameNormal() }
        )
    }

    private static func markerPairIsValid(
        around root: Element, in parent: Element,
        item: SVGIDNamespace.MarkedRoot, required: Bool
    ) -> Bool {
        // childNodesCopy() deep-copies SwiftSoup nodes, breaking identity.
        // This read-only pass must inspect the actual parsed siblings.
        let nodes = parent.getChildNodes()
        guard let index = nodes.firstIndex(where: { $0 === root }) else { return false }
        if !required {
            return true
        }
        guard index > 0, index + 1 < nodes.count,
              let before = nodes[index - 1] as? Comment,
              let after = nodes[index + 1] as? Comment else { return false }
        return item.startMarker == "<!--\(before.getData())-->"
            && item.endMarker == "<!--\(after.getData())-->"
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
