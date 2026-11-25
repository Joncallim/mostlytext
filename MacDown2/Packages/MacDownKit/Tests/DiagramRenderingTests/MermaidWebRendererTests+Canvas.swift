import AppKit
@testable import DiagramRendering
import Diagrams
import Foundation
import Testing
@testable import Themes

/// Canvas rasterization and pie-palette cases of the `MermaidWebRenderer`
/// suite, kept in an extension so the suite stays one Swift Testing suite.
extension MermaidWebRendererTests {
    @Test func wideAndTallDiagramsKeepVectorWhenPreviewRasterExceedsItsBudget() async throws {
        let renderer = MermaidWebRenderer(poolSize: 1)
        for direction in ["LR", "TD"] {
            let source = "graph \(direction)\n" + (0 ..< 64).map {
                "n\($0) --> n\($0 + 1)"
            }.joined(separator: "\n")
            do {
                let diagram = try await renderer.render(Self.fence(source), context: .neutralLight)
                #expect(diagram.svg.contains("<svg"))
                #expect(diagram.pngData == nil)
            } catch {
                await renderer.shutdown()
                throw error
            }
        }
        await renderer.shutdown()
    }

    @Test func explicitNodeColorsRemainAuthored() async throws {
        let renderer = MermaidWebRenderer()
        let source = "graph TD; A-->B; style A fill:#123456,stroke:#ABCDEF;"
        let diagram = try await renderer.render(Self.fence(source), context: MermaidRenderContext(
            foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
            backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
        ))
        #expect(diagram.svg.localizedCaseInsensitiveContains("#123456"))
        #expect(diagram.svg.localizedCaseInsensitiveContains("#ABCDEF"))
        await renderer.shutdown()
    }

    @Test func authoredInitAndFrontmatterColorsSurviveDarkScreenDefaults() async throws {
        let renderer = MermaidWebRenderer(poolSize: 1)
        let dark = MermaidRenderContext(
            foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
            backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
        )
        let sources = [
            "%%{init: {\"themeVariables\":{\"primaryColor\":\"#123456\","
                + "\"primaryTextColor\":\"#000000\",\"background\":\"#654321\"}}}%%\ngraph TD; A-->B;",
            """
            ---
            config:
              themeVariables:
                primaryColor: '#123456'
                primaryTextColor: '#000000'
                background: '#654321'
            ---
            graph TD; A-->B;
            """,
        ]
        for source in sources {
            let diagram = try await renderer.render(Self.fence(source), context: dark)
            #expect(diagram.svg.localizedCaseInsensitiveContains("#123456"))
            #expect(diagram.svg.localizedCaseInsensitiveContains(".node path{fill:#123456;"))
            #expect(diagram.svg.range(
                of: #"\.label\{[^}]*color:#000000;"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil)
            #expect(diagram.svg.contains(##"fill="#654321""##))
        }
        await renderer.shutdown()
    }

    @Test @MainActor func canvasRejectsMissingOrNonFiniteDimensions() async throws {
        for svg in [
            #"<svg xmlns="http://www.w3.org/2000/svg"/>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 NaN 80"/>"#,
        ] {
            await #expect(throws: Error.self) {
                _ = try await MermaidSVGProbe.canvasProbe(svg)
            }
        }
    }

    @Test @MainActor func rasterBudgetAdmitsBoundaryAndRejectsOversizeBeforeCanvasCreation() async throws {
        let page = try await MermaidHarnessPage.make()
        defer { page.teardown() }
        let admitted = try await page.inspectRasterSizeForTesting(width: 2048, height: 1024)
        #expect((admitted["width"] as? NSNumber)?.intValue == 4096)
        #expect((admitted["height"] as? NSNumber)?.intValue == 2048)
        for (width, height) in [(2048.5, 100.0), (2048.0, 1024.5), (1e308, 1.0)] {
            await #expect(throws: Error.self) {
                _ = try await page.inspectRasterSizeForTesting(width: width, height: height)
            }
        }
        await #expect(throws: Error.self) {
            _ = try await page.inspectSVGCanvasForTesting(
                #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1e308 1"/>"#
            )
        }
    }

    @Test @MainActor func canvasUsesNegativeOriginAndCommaSeparatedExponentViewBoxForPNG() async throws {
        let probe = try await MermaidSVGProbe.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10,-20,3.2e2,1.8e2">"#
                + #"<circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 320)
        #expect(probe.height == 180)
        #expect(probe.svg.contains(##"<rect x="-10" y="-20" width="320" height="180" fill="#FFFFFF""##))
        let png = try MermaidSVGProbe.pngDimensions(probe.pngData)
        #expect(png.width == 640)
        #expect(png.height == 360)
        let pixels = try MermaidSVGProbe.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test @MainActor func canvasFallsBackToNumericRootDimensionsWhenViewBoxIsMissing() async throws {
        let probe = try await MermaidSVGProbe.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180"><circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 320)
        #expect(probe.height == 180)
        #expect(probe.svg.contains(##"<rect x="0" y="0" width="320" height="180" fill="#FFFFFF""##))
        #expect(!probe.svg.contains("viewBox="))
        let png = try MermaidSVGProbe.pngDimensions(probe.pngData)
        #expect(png.width == 640)
        #expect(png.height == 360)
        let pixels = try MermaidSVGProbe.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test @MainActor func canvasFallsBackToNumericRootDimensionsWhenViewBoxIsInvalid() async throws {
        let probe = try await MermaidSVGProbe.canvasProbe(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 -320 180" width="240" height="135">"#
                + #"<circle cx="20" cy="20" r="10"/></svg>"#
        )
        #expect(probe.width == 240)
        #expect(probe.height == 135)
        #expect(probe.svg.contains(##"<rect x="0" y="0" width="240" height="135" fill="#FFFFFF""##))
        #expect(!probe.svg.contains("viewBox="))
        let png = try MermaidSVGProbe.pngDimensions(probe.pngData)
        #expect(png.width == 480)
        #expect(png.height == 270)
        let pixels = try MermaidSVGProbe.pngPixelEvidence(probe.pngData)
        #expect(pixels.hasOpaqueWhite)
        #expect(pixels.hasDiagramContent)
    }

    @Test func pieChartsUseDistinctMonochromeDefaultsUntilSourceStylesOverrideIt() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        pie title Categories
            "One" : 1
            "Two" : 2
            "Three" : 3
            "Four" : 4
            "Five" : 5
            "Six" : 6
            "Seven" : 7
            "Eight" : 8
            "Nine" : 9
            "Ten" : 10
            "Eleven" : 11
            "Twelve" : 12
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        let sliceCount = diagram.svg.components(separatedBy: "class=\"pieCircle\"").count - 1
        let legendSwatchCount = diagram.svg.components(separatedBy: "class=\"legend\"").count - 1
        #expect(sliceCount == 12)
        let expectedColors = DiagramPalette.neutralLight.pieColors
        #expect(expectedColors.count == 12)
        #expect(Set(expectedColors).count == 12)
        #expect(expectedColors.allSatisfy(diagram.svg.localizedCaseInsensitiveContains))
        #expect(legendSwatchCount >= 12)
        #expect(diagram.svg.range(
            of: ##"<g class="legend"[^>]*>.*fill: rgb\(26, 26, 26\)"##,
            options: [.regularExpression, .caseInsensitive]
        ) != nil, "no monochrome legend swatch")
        for generatedColor in ["#4E79A7", "#F28E2B", "#59A14F", "#E15759"] {
            #expect(!diagram.svg.localizedCaseInsensitiveContains(generatedColor))
        }
        await renderer.shutdown()
    }

    @Test func generatedGanttColorsUseTheResolvedMonochromePalette() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        gantt
            title Plan
            dateFormat  YYYY-MM-DD
            todayMarker off
            section Plan
            Ordinary : 2026-01-01, 1d
            Critical :crit, 2026-01-02, 1d
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        let viewBox = try MermaidSVGProbe.svgViewBox(in: diagram.svg)
        #expect(viewBox.width > 0)
        #expect(viewBox.height > 0)
        for generatedColor in ["#ff8888", "#ff0000", "#000080"] {
            #expect(!diagram.svg.localizedCaseInsensitiveContains(generatedColor))
        }
        #expect(diagram.svg.localizedCaseInsensitiveContains("#1A1A1A"))
        #expect(diagram.svg.localizedCaseInsensitiveContains("#FFFFFF"))
        await renderer.shutdown()
    }
}
