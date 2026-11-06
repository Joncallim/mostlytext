import Foundation
import SwiftSoup

extension HeadingSVGNamespace {
    /// Every rewritten root owns at least one ID, so more roots cannot pass
    /// the existing 4,096-ID final analysis budget. Reject before per-root DOM work.
    static let maximumRoots = 4096

    struct Root {
        let id: String
        let declaredIDs: Set<String>
        let references: Set<String>
    }

    struct Fragment {
        let html: String
        let roots: [Root]
    }

    private static let referenceParserLock = NSLock()

    /// Unlike the strict SVG route, ordinary rendering preserves absent local
    /// definitions. Every reference is still renamed into this occurrence, and
    /// final composition must prove an absent definition remains absent.
    static func rewrite(
        _ html: String, occurrence: Int, family: String, rootLimit: Int = maximumRoots
    ) -> Fragment? {
        guard SVGIDNamespace.validID(family), family.hasSuffix("-"), family.utf8.count <= 64 else { return nil }
        let scalars = Array(html.unicodeScalars)
        guard let ranges = SVGIDNamespace.findRoots(in: scalars), !ranges.isEmpty,
              ranges.count <= min(rootLimit, maximumRoots) else { return nil }
        return referenceParserLock.withLock {
            var output = ""
            var roots: [Root] = []
            var copiedThrough = 0
            for (ordinal, range) in ranges.enumerated() {
                let source = String(String.UnicodeScalarView(scalars[range]))
                guard let document = try? SwiftSoup.parseBodyFragment(source),
                      let elements = try? document.getAllElements().array(),
                      let references = SVGAssemblyOwnership.referenceTargets(in: elements),
                      references.allSatisfy(SVGIDNamespace.validID),
                      let rewritten = SVGIDNamespace.rewriteRoot(
                          source, prefix: "\(family)\(occurrence)-\(ordinal)-", additionalReferenceIDs: references
                      ), let record = record(rewritten) else { return nil }
                output += String(String.UnicodeScalarView(scalars[copiedThrough ..< range.lowerBound]))
                output += rewritten
                roots.append(record)
                copiedThrough = range.upperBound
            }
            output += String(String.UnicodeScalarView(scalars[copiedThrough...]))
            return Fragment(html: output, roots: roots)
        }
    }

    private static func record(_ html: String) -> Root? {
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let elements = try? document.getAllElements().array(),
              let root = elements.first(where: { $0.tagNameNormal() == "svg" }),
              let id = try? root.attr("id"), !id.isEmpty,
              let declared = SVGIDNamespace.collectIDs(in: Array(html.unicodeScalars)),
              let references = SVGAssemblyOwnership.referenceTargets(in: elements) else { return nil }
        return Root(id: id, declaredIDs: declared, references: references)
    }

    /// Called under the emitted-heading parser lock. Check actual browser-style
    /// tree ownership without serializing repaired authored markup back out.
    static func validate(elements: [Element], family: String?, roots: [Root]) -> Bool {
        guard let family else { return roots.isEmpty }
        let expected = Set(roots.flatMap(\.declaredIDs))
        guard expected.count == roots.reduce(0, { $0 + $1.declaredIDs.count }) else { return false }
        var actual: Set<String> = []
        var elementsByID: [String: Element] = [:]
        for element in elements {
            if let name = try? element.attr("name"), name.utf8.starts(with: family.utf8) {
                return false
            }
            if let id = try? element.attr("id"), id.utf8.starts(with: family.utf8) {
                guard expected.contains(id), actual.insert(id).inserted else { return false }
                elementsByID[id] = element
            }
        }
        guard actual == expected else { return false }
        for root in roots {
            guard let element = elementsByID[root.id],
                  element.tagNameNormal() == "svg",
                  let subtree = try? element.getAllElements().array(),
                  let references = SVGAssemblyOwnership.referenceTargets(in: subtree), references == root.references
            else { return false }
            let declared = Set(subtree.compactMap { $0.hasAttr("id") ? try? $0.attr("id") : nil })
            guard declared == root.declaredIDs,
                  root.references.subtracting(root.declaredIDs).isDisjoint(with: actual) else { return false }
        }
        return true
    }
}
