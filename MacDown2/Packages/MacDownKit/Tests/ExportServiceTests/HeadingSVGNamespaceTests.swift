@testable import ExportService
import Foundation
import SwiftSoup
import Testing

struct HeadingSVGNamespaceTests {
    @Test func theFirstUnoccupiedFamilyIsDisjointFromExactAuthoredPrefixes() {
        let identifiers = ["MTTOC-SVG-0-root", "MTTOC-SVG-2-node", "MTTOC-SVG-00-other", "mtTOC-SVG-1-case"]
        let family = HeadingSVGNamespace.family(avoiding: identifiers)
        #expect(family == "MTTOC-SVG-1-")
        #expect(identifiers.allSatisfy { !$0.utf8.starts(with: family.utf8) })
    }

    @Test func aCombiningMarkCannotHideAnOccupiedASCIIBytePrefix() {
        let identifier = "MTTOC-SVG-0-\u{301}root"
        #expect(identifier.utf8.starts(with: "MTTOC-SVG-0-".utf8))
        #expect(HeadingSVGNamespace.family(avoiding: [identifier]) == "MTTOC-SVG-1-")
    }

    @Test func aCompleteAdmittedInventoryStillHasABoundedAvailableFamily() {
        let identifiers = (0 ..< 4096).map { "MTTOC-SVG-\($0)-node" }
        #expect(HeadingSVGNamespace.family(avoiding: identifiers) == "MTTOC-SVG-4096-")
    }

    @Test func hostileNumbersAndLongSuffixesCannotOverflowOrGrowTheFamily() {
        let large = String(repeating: "9", count: 1_000_000)
        let identifiers = ["MTTOC-SVG-\(large)-node", "MTTOC-SVG-0-" + large]
        #expect(HeadingSVGNamespace.family(avoiding: identifiers) == "MTTOC-SVG-1-")
    }

    @Test func occurrenceNamespacesRewriteAllReferencesWithoutMutatingCanonicalArt() throws {
        let canonical = """
        <svg id="graph0"><style>#graph0 .node{clip-path:url(#clip);}</style>
        <defs><clipPath id="clip"><path id="path" /></clipPath></defs>
        <g class="node" aria-labelledby="label" clip-path="url(#clip)">
        <title id="label">Label</title><use href="#path" /></g></svg>
        """
        let before = Data(canonical.utf8)
        let family = HeadingSVGNamespace.family(avoiding: ["MTTOC-SVG-0-root"])
        var ids: Set<String> = []
        for occurrence in 0 ..< 2 {
            let html = try #require(SVGIDNamespace.rewrite(canonical, occurrence: occurrence, family: family))
            let prefix = family + String(occurrence) + "-0-"
            let dom = try SwiftSoup.parseBodyFragment(html)
            let local = try dom.select("[id]").array().map { try $0.attr("id") }
            #expect(local.count == 4 && local.allSatisfy { $0.utf8.starts(with: prefix.utf8) })
            #expect(local.allSatisfy { ids.insert($0).inserted })
            #expect(try dom.select("use").first()?.attr("href") == "#" + prefix + "path")
            #expect(try dom.select("g").first()?.attr("aria-labelledby") == prefix + "label")
            #expect(try dom.select("g").first()?.attr("clip-path") == "url(#" + prefix + "clip)")
            #expect(html.contains("#" + prefix + "graph0") && html.contains("url(#" + prefix + "clip)"))
            #expect(!html.contains("<!--MT117-"))
        }
        #expect(ids.count == 8 && Data(canonical.utf8) == before)
    }

    @Test func unsupportedUnicodeSVGIDsAndInvalidNamespaceSyntaxRetainExistingRejection() {
        #expect(SVGIDNamespace.rewrite("<svg id='café'></svg>", occurrence: 0, family: "MTTOC-SVG-0-") == nil)
        #expect(SVGIDNamespace.rewrite("<svg id='own'></svg>", occurrence: 0, family: "bad\"family-") == nil)
        #expect(SVGIDNamespace.rewrite("<svg id='own'></svg>", occurrence: 0, family: "unterminated") == nil)
    }
}
