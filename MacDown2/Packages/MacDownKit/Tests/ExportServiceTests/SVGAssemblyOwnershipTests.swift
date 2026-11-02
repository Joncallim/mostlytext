@testable import ExportService
import Foundation
import Testing
import Themes

@Suite("Exact assembled SVG ownership")
struct SVGAssemblyOwnershipTests {
    private let artwork = #"<svg id="root"><defs><linearGradient id="paint"/></defs>"#
        + #"<style>@keyframes pulse{to{opacity:1}}#root rect{fill:url(#paint);animation:pulse 1s}</style>"#
        + #"<rect fill="url(#paint)"/></svg>"#

    @Test func validRepeatedDiagramsPublishWithoutPrivateMarkers() throws {
        let first = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        let second = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 1))
        let combined = SVGIDNamespace.MarkedFragment(
            html: first.html + second.html, roots: first.roots + second.roots
        )
        let document = assembled(body: combined.html)
        let inspected = try #require(SVGAssemblyOwnership.inspect(markedDocument: document, fragment: combined))
        let published = try #require(SVGAssemblyOwnership.publish(
            markedDocument: document, fragment: combined, inspected: inspected
        ))
        #expect(!published.html.contains("<!--MT117-SVG-"))
        #expect(published.html.contains("mt117-svg-0-0-paint"))
        #expect(published.html.contains("mt117-svg-1-0-paint"))
        #expect(SVGAssemblyOwnership.stillMatches(published.html, publication: published))
        #expect(!SVGAssemblyOwnership.stillMatches(published.html + " ", publication: published))
    }

    @Test func outsideIDAndReferenceCannotBorrowTheDiagramNamespace() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        for outside in [
            #"<div id="mt117-svg-0-0-paint"></div>"#,
            #"<svg><rect fill="url(#mt117-svg-0-0-paint)"/></svg>"#,
            #"<div style="animation-name:mt117-svg-0-0-pulse"></div>"#,
            #"<div style="font-family:mt117-svg-0-0-demo"></div>"#,
        ] {
            let document = assembled(body: outside + marked.html)
            #expect(SVGAssemblyOwnership.inspect(markedDocument: document, fragment: marked) == nil)
        }
    }

    @Test func headDefinitionsAndUnparsedEscapesFailClosed() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        for stylesheet in [
            #"<style>@keyframes mt117-svg-0-0-pulse{to{opacity:0}}</style>"#,
            #"<style>@keyframes MT117-SVG-0-0-PULSE{to{opacity:0}}</style>"#,
            #"<style>[id="MT117-SVG-0-0-ROOT" i]{opacity:0}</style>"#,
            #"<style>@keyframes mt117-svg-0-0-\70ulse{to{opacity:0}}</style>"#,
            #"<style>@import url("data:text/css,ignored");</style>"#,
            #"<link rel="alternate stylesheet" href="styles.css">"#,
        ] {
            #expect(SVGAssemblyOwnership.inspect(
                markedDocument: assembled(body: marked.html, head: stylesheet), fragment: marked
            ) == nil)
        }
        let font = #"<svg id="root"><style>@font-face{font-family:Demo;"#
            + #"src:url("data:font/woff;base64,AA==")}#root text{font-family:Demo}</style>"#
            + "<text>Sample</text></svg>"
        let markedFont = try #require(SVGIDNamespace.rewriteMarked(font, occurrence: 4))
        let colliding = #"<style>@font-face{font-family:"MT117-SVG-4-0-DEMO";"#
            + #"src:url("data:font/woff;base64,AA==")}</style>"#
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: assembled(body: markedFont.html, head: colliding), fragment: markedFont
        ) == nil)
        let unrelated = #"<style>@keyframes outside{to{opacity:0}}"#
            + #"@font-face{font-family:Other;src:url("data:font/woff;base64,AA==")}</style>"#
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: assembled(body: markedFont.html, head: unrelated), fragment: markedFont
        ) == nil)
    }

    @Test func authoredBaseAndScriptsCannotChangeTheOptInResourcePolicy() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        for head in [
            #"<base href="file:///tmp/">"#,
            #"<base target="_blank">"#,
            #"<script>document.title='changed'</script>"#,
            #"<meta http-equiv="refresh" content="0;url=https://example.invalid/">"#,
        ] {
            #expect(SVGAssemblyOwnership.inspect(
                markedDocument: assembled(body: marked.html, head: head), fragment: marked
            ) == nil)
        }
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: assembled(body: marked.html + "<script></script>"), fragment: marked
        ) == nil)
    }

    @Test func changedTemplateOrRecomposedFragmentCannotReuseReceipt() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        let document = assembled(body: marked.html)
        let inspected = try #require(SVGAssemblyOwnership.inspect(markedDocument: document, fragment: marked))
        #expect(SVGAssemblyOwnership.publish(
            markedDocument: document.replacingOccurrences(of: "Example", with: "Changed"),
            fragment: marked, inspected: inspected
        ) == nil)
        let recomposed = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        #expect(SVGAssemblyOwnership.publish(
            markedDocument: assembled(body: recomposed.html), fragment: recomposed, inspected: inspected
        ) == nil)
    }

    @Test func changedMarkerInventoryCannotReuseReceiptForTheSameFragmentBytes() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        let document = assembled(body: "<!--FAKE-BEGIN-->" + marked.html + "<!--FAKE-END-->")
        let inspected = try #require(SVGAssemblyOwnership.inspect(
            markedDocument: document, fragment: marked
        ))
        let root = try #require(marked.roots.first)
        let forged = SVGIDNamespace.MarkedFragment(html: marked.html, roots: [
            SVGIDNamespace.MarkedRoot(
                startMarker: "<!--FAKE-BEGIN-->", endMarker: "<!--FAKE-END-->",
                rootID: root.rootID, ownedIDs: root.ownedIDs
            ),
        ])
        #expect(SVGAssemblyOwnership.publish(
            markedDocument: document, fragment: forged, inspected: inspected
        ) == nil)
    }

    @Test func browserReparentingOrMissingDefinitionsRejectsTheDocument() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: assembled(body: "<table>" + marked.html + "</table>"), fragment: marked
        ) == nil)
        let missing = marked.html.replacingOccurrences(of: #"<lineargradient id="mt117-svg-0-0-paint" />"#, with: "")
        #expect(missing != marked.html)
        let tampered = SVGIDNamespace.MarkedFragment(html: missing, roots: marked.roots)
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: assembled(body: tampered.html), fragment: tampered
        ) == nil)
    }

    @Test func actualExportWriterShapesNeedTheExactPublishableBytes() throws {
        let marked = try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: 0))
        let audited = try #require(SVGAssemblyOwnership.AuditedHeadCSS.builtIn(for: BundledThemes.light))
        let prepared = PreparedExportDocument(
            title: "Example", bodyHTML: marked.html,
            stylesheet: audited.stylesheet,
            manifest: ExportManifest(resources: [], referenceMap: [:]),
            diagnostics: [], sourceGeneration: 1, preservesRawHTML: false
        )
        let candidates = try [
            ExportHTMLWriter.selfContainedHTML(from: prepared),
            ExportHTMLWriter.selfContainedHTML(from: prepared, additionalHead:
                #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'">"#),
            ExportHTMLWriter.companionHTML(from: prepared, style: .embedded),
        ]
        for document in candidates {
            let receipt = try #require(SVGAssemblyOwnership.inspect(
                markedDocument: document, fragment: marked, auditedHeadCSS: audited
            ))
            let published = try #require(SVGAssemblyOwnership.publish(
                markedDocument: document, fragment: marked, inspected: receipt
            ))
            #expect(!published.html.contains(marked.roots[0].startMarker))
            #expect(SVGAssemblyOwnership.stillMatches(published.html, publication: published))
            #expect(!SVGAssemblyOwnership.stillMatches(
                published.html + " ", publication: published
            ))
        }
        let tamperedCSS = candidates[0].replacingOccurrences(
            of: audited.emittedStyleData,
            with: audited.emittedStyleData + "svg rect { fill: url(#outside) }"
        )
        #expect(tamperedCSS != candidates[0])
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: tamperedCSS, fragment: marked, auditedHeadCSS: audited
        ) == nil)
        let authoredStyle = candidates[0].replacingOccurrences(
            of: marked.html,
            with: #"<div style="--paint:url(#outside)">"# + marked.html + "</div>"
        )
        #expect(authoredStyle != candidates[0])
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: authoredStyle, fragment: marked, auditedHeadCSS: audited
        ) == nil)
        let linked = try ExportHTMLWriter.companionHTML(from: prepared, style: .linked)
        #expect(SVGAssemblyOwnership.inspect(
            markedDocument: linked, fragment: marked, auditedHeadCSS: audited
        ) == nil)
    }

    /// Opt-in Release package probe only; this is not full-app or WebKit RSS.
    @Test func assembledReleaseProbe() throws {
        guard ProcessInfo.processInfo.environment["MOSTLYTEXT_117_ASSEMBLY_RELEASE_PROBE"] == "1"
        else { return }
        let fragments = try (0 ..< 16).map { index in
            try #require(SVGIDNamespace.rewriteMarked(artwork, occurrence: index))
        }
        let combined = SVGIDNamespace.MarkedFragment(
            html: fragments.map(\.html).joined(), roots: fragments.flatMap(\.roots)
        )
        let document = assembled(body: "<p>" + String(repeating: "a", count: 1_000_000)
            + "</p>" + combined.html)
        let start = ContinuousClock.now
        let inspected = try #require(SVGAssemblyOwnership.inspect(markedDocument: document, fragment: combined))
        let publication = try #require(SVGAssemblyOwnership.publish(
            markedDocument: document, fragment: combined, inspected: inspected
        ))
        #expect(SVGAssemblyOwnership.stillMatches(publication.html, publication: publication))
        print("#117 assembly Release package probe: input=\(document.utf8.count)B "
            + "roots=\(combined.roots.count) elapsed=\(start.duration(to: ContinuousClock.now))")
    }

    private func assembled(body: String, head: String = "<style></style>") -> String {
        BuiltInExportTemplate.document(title: "Example", visibleTitle: "Visible", styleElement: head, body: body)
    }
}
