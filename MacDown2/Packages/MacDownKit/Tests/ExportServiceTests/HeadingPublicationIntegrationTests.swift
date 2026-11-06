@testable import Contributions
@testable import ExportService
import Foundation
import MarkdownEngine
import SwiftSoup
import Testing

struct HeadingPublicationIntegrationTests {
    @Test(arguments: ["id", "name"])
    func opaqueContributedIdentifiersCannotAliasAnOccurrenceNamespace(_ attribute: String) async throws {
        let source = "[TOC]\n\n# graph0\n\n```dot\none\n```\n\nOPAQUE\n"
        let initial = try await linkedRequest(source)
        let diagram = contribution("```dot\none\n```", in: source, html: "<svg id='graph0'></svg>")
        let opaque = contribution("OPAQUE", in: source, html: "<a \(attribute)='MTTOC-SVG-0-1-0-graph0'>Alias</a>")
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: initial.theme,
            contributions: initial.contributions + [diagram, opaque], headingPreparation: initial.headingPreparation
        )
        let error = await #expect(throws: ExportError.self) {
            _ = try await ExportService.prepare(request, target: target())
        }
        guard case .headingNavigationUnavailable = error else {
            Issue.record("Opaque aliases must fail the final namespace inventory")
            return
        }
    }

    @Test func rejectedRequiredTOCsCannotSilentlyBecomeSourceOrAnotherContribution() async throws {
        let source = "\n[TOC]\n\n# Target\n"
        let initial = try await linkedRequest(source)
        let toc = try #require(initial.contributions.first)
        let stale = ExportDerivedContribution(
            sourceRange: toc.sourceRange, placement: toc.placement, html: toc.html,
            sourceGeneration: 0, requiresHeadingNavigation: true
        )
        let empty = ExportDerivedContribution(
            sourceRange: toc.sourceRange, placement: toc.placement, html: "",
            sourceGeneration: 1, requiresHeadingNavigation: true
        )
        let overlapping = ExportDerivedContribution(
            sourceRange: 0 ..< toc.sourceRange.upperBound + 1, placement: .block,
            html: "<p>Other contribution</p>", sourceGeneration: 1
        )
        let cases: [([ExportDerivedContribution], HeadingAnchorPreparation?)] = [
            ([stale], initial.headingPreparation), ([empty], initial.headingPreparation),
            ([overlapping, toc], initial.headingPreparation), ([toc, toc], initial.headingPreparation), ([toc], nil),
        ]
        for (contributions, preparation) in cases {
            let request = ExportRequest(
                text: source, sourceGeneration: 1, theme: initial.theme,
                contributions: contributions, headingPreparation: preparation
            )
            let error = await #expect(throws: ExportError.self) {
                _ = try await ExportService.prepare(request, target: target())
            }
            guard case .headingNavigationUnavailable = error else {
                Issue.record("A rejected required TOC must fail before publication")
                continue
            }
        }
    }

    @Test func repeatedDiagramsCannotStealTheHeadingOrAnAuthoredNamespaceFamily() async throws {
        let source = "<div id='MTTOC-SVG-0-\u{301}root'>Raw</div>\n\n[TOC]\n\n# graph0\n\n"
            + "```dot\none\n```\n\n```dot\ntwo\n```\n"
        let initial = try await linkedRequest(source)
        let canonical = "<svg id='graph0'><path id='node1' /><use href='#node1' /></svg>"
        let diagrams = ["one", "two"].map {
            contribution("```dot\n\($0)\n```", in: source, html: canonical)
        }
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: initial.theme,
            contributions: initial.contributions + diagrams, headingPreparation: initial.headingPreparation
        )
        let prepared = try await ExportService.prepare(request, target: target())
        let dom = try SwiftSoup.parseBodyFragment(prepared.bodyHTML)
        #expect(try dom.select("h1").first()?.attr("id") == "graph0")
        #expect(try dom.select("li a").first()?.attr("href") == "#graph0")
        let roots = try dom.select("svg").array()
        #expect(roots.count == 2)
        #expect(try roots.map { try $0.attr("id") } == ["MTTOC-SVG-1-1-0-graph0", "MTTOC-SVG-1-2-0-graph0"])
        let ids = try dom.select("[id]").array().map { try Data($0.attr("id").utf8) }
        #expect(Set(ids).count == ids.count)
        #expect(!prepared.bodyHTML.contains("<!--MT117-"))
        #expect(canonical == "<svg id='graph0'><path id='node1' /><use href='#node1' /></svg>")
    }

    @Test func noHeadingPlaceholderNeedsNoTargetAuthorityEvenBesideRawHTML() async throws {
        let source = "[TOC]\n\n<div id=authored>Raw</div>\n"
        let prepared = try await ExportService.prepare(linkedRequest(source), target: target())
        #expect(prepared.bodyHTML.contains("No headings found."))
        #expect(prepared.bodyHTML.contains("<div id=authored>Raw</div>"))
        #expect(!prepared.bodyHTML.contains("href=") && !prepared.bodyHTML.contains("MT117-"))
    }

    @Test func linkedTOCReachesEachOriginalHeadingAfterFrontMatterAndSplicing() async throws {
        let source = "---\ntitle: Title\n---\n\n[TOC]\n\n# A\n\n## A\n\n# A-1\n\n# Café 東京\n"
        let request = try await linkedRequest(source)
        let prepared = try await ExportService.prepare(request, target: target())
        let dom = try SwiftSoup.parseBodyFragment(prepared.bodyHTML)
        let headings = try dom.select("h1[id], h2[id]").array()
        let fragments = try #require(request.headingIndex).headings.map(\.fragment)
        #expect(try headings.map { try $0.attr("id") } == fragments)
        #expect(try dom.select("li a").array().map { try $0.attr("href").removingPercentEncoding } ==
            fragments.map { "#" + $0 })
        #expect(!prepared.bodyHTML.contains("MT117-") && !prepared.bodyHTML.contains("E12BLOCK"))
    }

    @Test func generatedImageSlotsAreMintedAfterHeadingAttributesOnBothSides() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try ExportTestSupport.writeFixture(named: "a.png", in: directory, bytes: bytes)
        let source = "![before](a.png)\n\n[TOC]\n\n# Café 東京\n\n![after](a.png)\n\n## Last\n"
        let initial = try await linkedRequest(source)
        let request = try ExportRequest(
            text: source, sourceGeneration: 1, theme: initial.theme,
            resourceAccess: ExportResourceAccess(openingDirectory: directory),
            contributions: initial.contributions, headingPreparation: initial.headingPreparation
        )
        let prepared = try await ExportService.prepare(
            request, target: target(directory.appendingPathComponent("é % # ?.html"))
        )
        let slots = try #require(prepared.resourceSlots)
        #expect(slots.occurrences.count == 2)
        try slots.validate(body: prepared.bodyHTML, manifest: prepared.manifest)
        let embedded = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(embedded.components(separatedBy: "data:image/png;base64,").count == 3)
        #expect(embedded.contains("id=\"café-東京\"") && embedded.contains("id=\"last\""))
        #expect(!embedded.contains("MTRESOURCE"))
    }

    @Test func pureLinkedExportAboveDOMBudgetRetainsOrdinarySourceAdmission() async throws {
        let source = "[TOC]\n\n# Target\n\n" + String(repeating: "ordinary text ", count: 650_000)
        let prepared = try await ExportService.prepare(linkedRequest(source), target: target())
        #expect(prepared.bodyHTML.utf8.count > EmittedHeadingDOM.maximumAnalyzedBytes)
        #expect(prepared.bodyHTML.contains("<h1 id=\"target\">Target</h1>"))
        #expect(prepared.bodyHTML.contains("href=\"#target\""))
    }

    @Test func noOptInExportKeepsItsOriginalHeadingAndRawHTMLPolicy() async throws {
        let source = "<div id=target>Raw</div>\n\n# Target\n"
        let request = ExportRequest(text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme())
        let prepared = try await ExportService.prepare(request, target: target())
        #expect(prepared.bodyHTML.contains("<h1>Target</h1>"))
        #expect(prepared.bodyHTML.contains("<div id=target>Raw</div>"))
        #expect(!prepared.bodyHTML.contains("MT117-"))
    }

    @Test func exactAuthoredReservationsSurviveTheFinalRawHTMLDOMPath() async throws {
        let source = "<div id='cafe&#x301;'>Raw</div>\n<a name='caf&#233;'>Legacy</a>\n\n[TOC]\n\n# Café\n"
        let prepared = try await ExportService.prepare(linkedRequest(source), target: target())
        let dom = try SwiftSoup.parseBodyFragment(prepared.bodyHTML)
        #expect(try dom.select("h1").first()?.attr("id") == "café-1")
        #expect(try dom.select("li a").first()?.attr("href").removingPercentEncoding == "#café-1")
        #expect(prepared.bodyHTML.contains("<div id='cafe&#x301;'>Raw</div>"))
    }

    @Test func opaqueContributedIdentifierCannotStealARequestedTarget() async throws {
        let source = "[TOC]\n\n# Target\n\nREPLACE\n"
        let initial = try await linkedRequest(source)
        let opaque = contribution("REPLACE", in: source, html: "<div id=target>Opaque</div>")
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: initial.theme,
            contributions: initial.contributions + [opaque], headingPreparation: initial.headingPreparation
        )
        let error = await #expect(throws: ExportError.self) {
            _ = try await ExportService.prepare(request, target: target())
        }
        guard case .headingNavigationUnavailable = error else {
            Issue.record("Expected the specific heading-navigation failure")
            return
        }
    }

    @Test func staleGenerationAndDifferentSourceCannotBorrowAnIndex() async throws {
        let initial = try await linkedRequest("[TOC]\n\n# Target\n")
        for (source, generation) in [(initial.text, UInt(2)), ("[TOC]\n\n# Changed\n", UInt(1))] {
            let request = ExportRequest(
                text: source, sourceGeneration: generation, theme: initial.theme,
                headingPreparation: initial.headingPreparation
            )
            let error = await #expect(throws: ExportError.self) {
                _ = try await ExportService.prepare(request, target: target())
            }
            guard case .headingNavigationUnavailable = error else {
                Issue.record("Expected a stale index to fail heading verification")
                continue
            }
        }
    }

    @Test func sentinelRetryRebuildsCoordinatesBeforePublishingLaterHeadings() async throws {
        let source = "[TOC]\n\n[link](other.md \"REPLACE\")\n\n# Target\n"
        let initial = try await linkedRequest(source)
        let impossible = contribution("REPLACE", in: source, html: "<em>replacement</em>", placement: .inline)
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: initial.theme,
            contributions: initial.contributions + [impossible], headingPreparation: initial.headingPreparation
        )
        let prepared = try await ExportService.prepare(request, target: target())
        #expect(prepared.bodyHTML.contains("title=\"REPLACE\""))
        #expect(prepared.bodyHTML.contains("<h1 id=\"target\">Target</h1>"))
        #expect(prepared.diagnostics.contains { $0.message.contains("cannot be placed") })
        #expect(!prepared.bodyHTML.contains("E12INLINE"))
    }

    @Test func failedFinalTargetVerificationPreservesPrimaryAndCompanionBytes() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.html")
        let companion = directory.appendingPathComponent("report.assets/keep.txt")
        try Data("previous primary".utf8).write(to: destination)
        try FileManager.default.createDirectory(
            at: companion.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("previous companion".utf8).write(to: companion)
        let source = "[TOC]\n\n# Target\n\nREPLACE\n"
        let initial = try await linkedRequest(source)
        let conflict = contribution("REPLACE", in: source, html: "<a name=target>Conflict</a>")
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: initial.theme,
            contributions: initial.contributions + [conflict],
            headingPreparation: initial.headingPreparation
        )
        let error = await #expect(throws: ExportError.self) {
            _ = try await ExportService.exportHTML(request, to: target(destination))
        }
        guard case .headingNavigationUnavailable = error else {
            Issue.record("Expected validation to fail before publication")
            return
        }
        #expect(try Data(contentsOf: destination) == Data("previous primary".utf8))
        #expect(try Data(contentsOf: companion) == Data("previous companion".utf8))
    }

    @Test func admittedFragmentsDoNotConsumeTheFollowingHeadingInTheRealHTMLParser() throws {
        let fragments = [
            "<ul><li><a href='#target'>Target</a><ul><li>Child</li></ul></li></ul>",
            "<p><em>Readable</em></p>", "<img src='data:image/png;base64,AAAA' alt='&quot;&lt;h1&gt;'>",
            "<ol start='9'><li><p>A</p><p>B</p></li></ol>",
        ]
        for fragment in fragments {
            try #require(HeadingFragmentStructure.accepts(fragment, isBlock: true))
            let dom = try SwiftSoup.parseBodyFragment("<div>Before</div>" + fragment + "<h1 id='target'>Target</h1>")
            let heading = try #require(dom.select("h1").first())
            #expect(try heading.attr("id") == "target")
            #expect(heading.parent()?.tagNameNormal() == "body")
            #expect(try dom.select("[id]").count == 1 && dom.select("a[name]").isEmpty())
        }
    }
}

extension HeadingPublicationIntegrationTests {
    private func linkedRequest(_ source: String) async throws -> ExportRequest {
        let document = try await ParseEngine().parse(source, revision: 1)
        let preparation = try await HeadingAnchorPreparation.prepare(
            document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(), sourceGeneration: 1
        )
        let markdown = TOCContribution.linkedMarkdownList(for: preparation.index)
        let html = ExportService.renderMarkdownFragment(markdown)
        try #require(HeadingFragmentStructure.accepts(html, isBlock: true))
        return ExportRequest(
            text: source, sourceGeneration: 1, theme: ExportTestSupport.lightTheme(),
            contributions: [contribution("[TOC]", in: source, html: html)], headingPreparation: preparation
        )
    }

    private func contribution(
        _ needle: String, in source: String, html: String, placement: ExportDerivedPlacement = .block
    ) -> ExportDerivedContribution {
        let range = (source as NSString).range(of: needle)
        return ExportDerivedContribution(
            sourceRange: range.location ..< range.location + range.length, placement: placement,
            html: html, sourceGeneration: 1, requiresHeadingNavigation: needle == "[TOC]"
        )
    }

    private func target(_ url: URL = URL(fileURLWithPath: "/tmp/heading-publication.html")) -> ExportTarget {
        .html(url: url, mode: .standalone(style: .embedded))
    }
}
