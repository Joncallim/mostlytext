import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes

/// Slice 1: ordinary deterministic HTML, URL security, metadata, theme, and
/// template. Exercises the full composer through the public `ExportService`.
struct ExportComposerTests {
    @Test func ordinaryHTMLPreservesAuthoredRawHTML() async throws {
        let markdown = "# Hi\n\n<div class=\"note\">raw</div>\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 2, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.preservesRawHTML)
        #expect(prepared.bodyHTML.contains("<div class=\"note\">raw</div>"))
    }

    @Test func selfContainedHTMLRejectsAuthoredRawHTML() async throws {
        // A self-contained document cannot prove that arbitrary raw HTML is
        // closed, so it fails rather than quietly dropping the author's markup.
        let markdown = "# Hi\n\n<div class=\"note\">raw</div>\n"
        let thrown = await #expect(throws: ExportError.self) {
            _ = try await ExportService.prepare(
                ExportRequest(text: markdown, sourceGeneration: 3, theme: ExportTestSupport.lightTheme()),
                target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
            )
        }
        #expect(thrown?.description.contains("raw HTML") == true)
    }

    @Test func selfContainedHTMLAcceptsDocumentsWithoutRawHTML() async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hi\n\nplain\n", sourceGeneration: 3, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(!prepared.preservesRawHTML)
        #expect(prepared.bodyHTML.contains("<h1>Hi</h1>"))
    }

    @Test func selfContainedEmbedsLocalImageAsDataURI() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        try ExportTestSupport.writeFixture(named: "images/foo.png", in: directory, bytes: bytes)

        let markdown = "# Img\n\n![alt](images/foo.png)\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 4,
                theme: ExportTestSupport.lightTheme(),
                documentURL: directory.appendingPathComponent("doc.md"),
                resourceAccess: ExportResourceAccess(openingDirectory: directory)
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )

        #expect(prepared.manifest.resources.count == 1)
        let resource = try #require(prepared.manifest.resources.first)
        #expect(resource.identity.mimeType == "image/png")

        let html = try ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("data:image/png;base64,"))
        #expect(!html.contains("images/foo.png"))
    }

    @Test func selfContainedFailsOnMissingLocalImage() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let markdown = "# Img\n\n![alt](missing.png)\n"
        await #expect(throws: ExportError.self) {
            _ = try await ExportService.prepare(
                ExportRequest(
                    text: markdown,
                    sourceGeneration: 5,
                    theme: ExportTestSupport.lightTheme(),
                    documentURL: directory.appendingPathComponent("doc.md"),
                    resourceAccess: ExportResourceAccess(openingDirectory: directory)
                ),
                target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
            )
        }
    }

    @Test func ordinaryHTMLWarnsOnMissingLocalImageButContinues() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let markdown = "# Img\n\n![alt](missing.png)\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 6,
                theme: ExportTestSupport.lightTheme(),
                documentURL: directory.appendingPathComponent("doc.md"),
                resourceAccess: ExportResourceAccess(openingDirectory: directory)
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.diagnostics.contains { $0.severity == .warning && $0.message.contains("missing.png") })
        #expect(prepared.bodyHTML.contains("missing.png"))
    }

    @Test func dangerousAuthoredLinkIsBlanked() async throws {
        let markdown = "[x](javascript:alert(1))\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 7, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(!prepared.bodyHTML.contains("javascript:"))
    }

    @Test func themeVariablesAppearInStylesheet() async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hi", sourceGeneration: 8, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.stylesheet.contains("--md-background"))
        #expect(prepared.stylesheet.contains("--md-foreground"))
    }

    @Test func pdfTargetCarriesNoHTMLOptions() async throws {
        // PDF composition uses the ordinary raw-HTML policy and requires
        // resolvable resources, but never embeds into a linked-CSS shape.
        let markdown = "# Hi\n\n<div>x</div>\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 9, theme: ExportTestSupport.lightTheme()),
            target: .pdf(url: URL(fileURLWithPath: "/tmp/out.pdf"))
        )
        #expect(prepared.preservesRawHTML)
        // Raw HTML survives the print pass, but only best-effort — the user is
        // told rather than left to discover it in the PDF.
        #expect(prepared.diagnostics.contains { $0.severity == .warning && $0.message.contains("raw HTML") })
    }

    @Test func sourceGenerationIsCarriedAsUInt() async throws {
        let generation: UInt = 123_456
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hi", sourceGeneration: generation, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.sourceGeneration == generation)
    }

    @Test func theThemeOwnsTheOnScreenColorScheme() async throws {
        // The theme block is emitted first and only the print block may follow
        // it; a dark export must not render with light-mode UA widgets.
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hi", sourceGeneration: 10, theme: BundledThemes.dark),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        let declared = prepared.stylesheet
            .components(separatedBy: "color-scheme:")
            .dropFirst()
            .map { segment in segment.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces) }
        // The theme's scheme comes first; anything after it belongs to @media print.
        #expect(declared.first == "dark")
        #expect(declared.count == 2)
    }

    @Test func exportErrorsCarryPresentableProse() {
        // The app shows `localizedDescription`; without `LocalizedError` that is
        // an opaque "operation couldn't be completed" string.
        let error = ExportError.rawHTMLNotEmbeddable
        #expect(error.localizedDescription.contains("raw HTML"))
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test func repeatedImageReferenceIsReadAndReportedOnce() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExportTestSupport.writeFixture(named: "logo.png", in: directory, bytes: Data([0x89, 0x50, 0x4E]))

        let markdown = "![a](logo.png)\n\n![b](logo.png)\n\n![c](gone.png)\n\n![d](gone.png)\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 11,
                theme: ExportTestSupport.lightTheme(),
                documentURL: directory.appendingPathComponent("doc.md"),
                resourceAccess: ExportResourceAccess(openingDirectory: directory)
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.manifest.resources.count == 1)
        // One broken image is one problem, however many times it is referenced.
        #expect(prepared.diagnostics.filter { $0.message.contains("gone.png") }.count == 1)
    }
}
