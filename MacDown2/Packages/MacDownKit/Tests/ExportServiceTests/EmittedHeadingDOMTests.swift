@testable import ExportService
import Foundation
import MarkdownEngine
import SwiftSoup
import Testing

@Suite("Emitted heading DOM targets")
struct EmittedHeadingDOMTests {
    @Test func authoredIDsReserveFragmentsAndTheAuthoredHTMLBytesSurvive() async throws {
        let source = """
        # Overview

        <div id=overview data-sourcepos="1:1-1:10">Raw</div>

        # Overview

        <!--MT117-forged-0-->
        """
        let fixture = try await makeFixture(source)
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs.contains("overview"))
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        #expect(index.headings.map(\.fragment) == ["overview-1", "overview-2"])
        #expect(html.contains("<div id=overview data-sourcepos=\"1:1-1:10\">Raw</div>"))
        #expect(html.contains("<h1 id=\"overview-1\">Overview</h1>"))
        #expect(html.contains("<h1 id=\"overview-2\">Overview</h1>"))
        #expect(html.contains("<!--MT117-forged-0-->"))
        #expect(!fixture.rendered.headingMarkers.contains { html.contains($0.comment) })
    }

    @Test func emittedTagfilterOutputRatherThanRawSourceReservesItsLiveID() async throws {
        let source = """
        <script>let example = '<b id=scripted>'</script>

        # Scripted
        """
        let fixture = try await makeFixture(source)
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs.contains("scripted"))
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        #expect(index.headings.map(\.fragment) == ["scripted-1"])
        #expect(html.contains("<h1 id=\"scripted-1\">Scripted</h1>"))
    }

    @Test func decodedUnicodeIDReservesTheExactFragment() async throws {
        let source = "<div id='caf&#233;'>Raw</div>\n\n# Café\n\n## 中文\n"
        let fixture = try await makeFixture(source)
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs.contains("café"))
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        #expect(index.headings.map(\.fragment) == ["café-1", "中文"])
        #expect(html.contains("<h1 id=\"café-1\">Café</h1>"))
        #expect(html.contains("<h2 id=\"中文\">中文</h2>"))
    }

    @Test func aWrongInventoryCannotPublishAConflictingTarget() async throws {
        let source = "<a name=legacy>Authored</a>\n\n# Legacy\n"
        let fixture = try await makeFixture(source)
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs.contains("legacy"))
        let wrongIndex = try index(for: fixture, reservedIDs: [])
        let matches = try #require(match(fixture, index: wrongIndex))
        #expect(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ) == nil)
    }

    @Test func anAuthoredCopyOfThePrivateMarkerIsRejected() async throws {
        let fixture = try await makeFixture("# Title\n")
        let marker = try #require(fixture.rendered.headingMarkers.first)
        let forged = CMarkGFM.Rendered(
            html: fixture.rendered.html + "<h1>\(marker.comment)Forged</h1>",
            containsRawHTML: fixture.rendered.containsRawHTML,
            headingLocations: fixture.rendered.headingLocations,
            headingMarkers: fixture.rendered.headingMarkers,
            headingSourceSHA256: fixture.rendered.headingSourceSHA256
        )
        #expect(EmittedHeadingDOM.inspect(forged) == nil)
    }

    @Test func malformedHTMLCannotSilentlyRetargetAHeading() async throws {
        let fixture = try await makeFixture("<div title='unterminated>\n\n# Target\n")
        #expect(EmittedHeadingDOM.inspect(fixture.rendered) == nil)
    }

    @Test func explicitIDBudgetRejectsAnOversizedAnchorInventory() async throws {
        let source = String(repeating: "<span id=x></span>\n", count: EmittedHeadingDOM.maximumExplicitIDs + 1)
            + "\n# Target\n"
        let fixture = try await makeFixture(source)
        #expect(EmittedHeadingDOM.inspect(fixture.rendered) == nil)
    }

    @Test func analyzedMarkupBudgetRejectsBeforeParsing() async throws {
        let fixture = try await makeFixture("# Target\n")
        let oversized = CMarkGFM.Rendered(
            html: fixture.rendered.html + String(repeating: "x", count: EmittedHeadingDOM.maximumAnalyzedBytes),
            containsRawHTML: fixture.rendered.containsRawHTML,
            headingLocations: fixture.rendered.headingLocations,
            headingMarkers: fixture.rendered.headingMarkers,
            headingSourceSHA256: fixture.rendered.headingSourceSHA256
        )
        #expect(EmittedHeadingDOM.inspect(oversized) == nil)
    }

    @Test func sourceMappingSurvivesDerivedBlockAndInlineSplices() async throws {
        let source = """
        ---
        title: Document
        ---

        # First

        ```diagram
        node
        ```

        Paragraph $x$.

        ## Last
        """
        let block = try #require(range(of: "```diagram\nnode\n```", in: source))
        let inline = try #require(range(of: "$x$", in: source))
        let fixture = try await makeFixture(source, contributions: [
            ExportDerivedContribution(
                sourceRange: block, placement: .block,
                html: "<svg id=diagram>Diagram</svg>", sourceGeneration: 1
            ),
            ExportDerivedContribution(
                sourceRange: inline, placement: .inline,
                html: "<span>x</span>", sourceGeneration: 1
            ),
        ])
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs.contains("mt117-svg-0-0-diagram"))
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        #expect(matches.map(\.emitted.level) == [1, 2])
        #expect(html.contains("<svg id=\"mt117-svg-0-0-diagram\">Diagram</svg>"))
        #expect(html.contains("<h2 id=\"last\">Last</h2>"))
    }

    @Test func repeatedSVGArtworkCannotStealTheGraphHeadingTarget() async throws {
        let source = "# graph0\n\n```diagram\nfirst\n```\n\n```diagram\nsecond\n```\n"
        let first = try #require(range(of: "```diagram\nfirst\n```", in: source))
        let second = try #require(range(of: "```diagram\nsecond\n```", in: source))
        let canonical = ##"<svg id="graph0"><use href="#graph0" /></svg>"##
        let fixture = try await makeFixture(source, contributions: [first, second].map {
            ExportDerivedContribution(sourceRange: $0, placement: .block, html: canonical, sourceGeneration: 1)
        })
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs == ["mt117-svg-0-0-graph0", "mt117-svg-1-0-graph0"])
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        #expect(index.headings.map(\.fragment) == ["graph0"])
        #expect(html.contains("<h1 id=\"graph0\">graph0</h1>"))
        #expect(html.contains(##"href="#mt117-svg-0-0-graph0""##))
        #expect(html.contains(##"href="#mt117-svg-1-0-graph0""##))
    }

    @Test func authoredIDMatchingAnSVGNamespaceFailsTheOptInAnalysis() async throws {
        let source = "<div id=mt117-svg-0-0-graph0>Authored</div>\n\n# Heading\n\n```diagram\nsource\n```\n"
        let fence = try #require(range(of: "```diagram\nsource\n```", in: source))
        let fixture = try await makeFixture(source, contributions: [
            ExportDerivedContribution(
                sourceRange: fence, placement: .block,
                html: "<svg id=graph0></svg>", sourceGeneration: 1
            ),
        ])
        #expect(EmittedHeadingDOM.inspect(fixture.rendered) == nil)
    }

    /// Run explicitly in Release for phase timing; package-process timings do
    /// not stand in for the signed app or WebKit's child-process memory.
    @Test func oneMiBTechnicalDocumentReleaseProbe() async throws {
        guard ProcessInfo.processInfo.environment["MOSTLYTEXT_117_RELEASE_PROBE"] == "1" else { return }
        let paragraph = String(repeating: "Technical text with Unicode 中 and math $x$; ", count: 512)
        let source = String(repeating: "# Section\n\n\(paragraph)\n\n", count: 48)
        #expect(source.utf8.count > 1_000_000)

        let start = ContinuousClock.now
        let fixture = try await makeFixture(source)
        let afterRender = ContinuousClock.now
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        let afterInspection = ContinuousClock.now
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        let afterValidation = ContinuousClock.now
        #expect(matches.count == 48)
        #expect(html.contains("<h1 id=\"section-47\">Section</h1>"))
        print("#117 Release package probe: source=\(source.utf8.count)B "
            + "parse+render=\(start.duration(to: afterRender)) "
            + "inspect=\(afterRender.duration(to: afterInspection)) "
            + "patch+validate=\(afterInspection.duration(to: afterValidation))")
    }

    private struct Fixture {
        let source: String
        let document: MarkdownDocument
        let derived: DerivedContentComposer.Result
        let rendered: CMarkGFM.Rendered
    }

    private func makeFixture(
        _ source: String,
        contributions: [ExportDerivedContribution] = []
    ) async throws -> Fixture {
        let document = try await ParseEngine().parse(source, revision: 1)
        let bodyStart = source.utf16.count - document.body.utf16.count
        let derived = DerivedContentComposer.compose(
            bodyText: document.body, bodyStartOffset: bodyStart,
            sourceUTF16Length: source.utf16.count, contributions: contributions,
            sourceGeneration: 1, recordCoordinates: true, namespaceSVGIDs: true
        )
        let rendered = try CMarkGFM.render(
            derived.splicedBody, options: CMarkGFM.optUnsafe,
            customNodes: derived.customNodes, headingAnalysis: .marked
        )
        return Fixture(source: source, document: document, derived: derived, rendered: rendered)
    }

    private func index(for fixture: Fixture, reservedIDs: [String]) throws -> HeadingAnchorIndex {
        try HeadingAnchorIndex(
            document: fixture.document, sourceText: fixture.source, documentID: "fixture",
            recoveryEpoch: UUID(), sourceGeneration: 1, reservedIDs: reservedIDs
        )
    }

    private func match(_ fixture: Fixture, index: HeadingAnchorIndex) -> [EmittedHeadingMatcher.Match]? {
        EmittedHeadingMatcher.match(
            index: index, document: fixture.document, sourceText: fixture.source,
            derived: fixture.derived, rendered: fixture.rendered
        )
    }

    private func range(of needle: String, in text: String) -> Range<Int>? {
        let match = (text as NSString).range(of: needle)
        guard match.location != NSNotFound else { return nil }
        return match.location ..< (match.location + match.length)
    }
}

extension EmittedHeadingDOMTests {
    @Test func completeBuiltInTemplateKeepsPublishedTargetsUnique() async throws {
        let source = "# graph0\n\n```diagram\nsource\n```\n"
        let fence = try #require(range(of: "```diagram\nsource\n```", in: source))
        let fixture = try await makeFixture(source, contributions: [
            ExportDerivedContribution(
                sourceRange: fence, placement: .block,
                html: ##"<svg id="graph0"><use href="#graph0" /></svg>"##, sourceGeneration: 1
            ),
        ])
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        let matches = try #require(match(fixture, index: index))
        let body = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        for headExtras in ["", #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'">"#] {
            let html = BuiltInExportTemplate.document(
                title: "Example", visibleTitle: "Visible", headExtras: headExtras,
                styleElement: "<style>body { color: black; }</style>", body: body
            )
            let dom = try SwiftSoup.parse(html)
            let heading = try #require(try dom.getElementById("graph0"))
            #expect(heading.tagNameNormal() == "h1")
            let svg = try #require(try dom.getElementById("mt117-svg-0-0-graph0"))
            #expect(svg.tagNameNormal() == "svg")
            let identifiers = try dom.getAllElements().array().filter { $0.hasAttr("id") }
                .map { try $0.attr("id") }
            #expect(Set(identifiers).count == identifiers.count)
            #expect(identifiers.count == 2)
            #expect(try dom.select("body > h1").size() == 2)
        }
    }
}

extension EmittedHeadingDOMTests {
    @Test(arguments: ["<div id='cafe&#x301;'>Raw</div>", "<a name='cafe&#x301;'>Raw</a>"])
    func canonicallyEquivalentAuthoredIDDoesNotStealTheGeneratedTarget(_ authored: String) async throws {
        let fixture = try await makeFixture(authored + "\n\n# Café\n")
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        try #require(inspection.reservedIDs.count == 1)
        #expect(inspection.reservedIDs[0].utf8.elementsEqual("cafe\u{301}".utf8))
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        #expect(index.headings.map(\.fragment) == ["café"])
        let matches = try #require(match(fixture, index: index))
        let html = try #require(EmittedHeadingDOM.publish(
            inspected: inspection, rendered: fixture.rendered, matches: matches
        ))
        #expect(html.range(of: authored, options: .literal) != nil)
        #expect(html.contains("<h1 id=\"café\">Café</h1>"))
    }

    @Test func inventoryPreservesBothAuthoredUnicodeSpellingsAndExactCollisionRefusal() async throws {
        let fixture = try await makeFixture("<div id='cafe&#x301;'>A</div>\n<div id='caf&#233;'>B</div>\n\n# Café\n")
        let inspection = try #require(EmittedHeadingDOM.inspect(fixture.rendered))
        #expect(inspection.reservedIDs.count == 2)
        #expect(Set(inspection.reservedIDs.map { Data($0.utf8) }).count == 2)
        let index = try index(for: fixture, reservedIDs: inspection.reservedIDs)
        #expect(index.headings.map(\.fragment) == ["café-1"])
        let matches = try #require(match(fixture, index: index))
        #expect(EmittedHeadingDOM.publish(inspected: inspection, rendered: fixture.rendered, matches: matches) != nil)
        let wrong = try self.index(for: fixture, reservedIDs: [])
        let wrongMatches = try #require(match(fixture, index: wrong))
        #expect(EmittedHeadingDOM
            .publish(inspected: inspection, rendered: fixture.rendered, matches: wrongMatches) == nil)
    }
}
