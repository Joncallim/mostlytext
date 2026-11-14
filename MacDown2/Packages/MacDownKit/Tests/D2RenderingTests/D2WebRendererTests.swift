import AppKit
@testable import D2Rendering
import DiagramsD2
import Foundation
import Testing

/// Real, end-to-end pipeline tests — genuine WebKit, genuine bundled D2,
/// no fakes — matching this codebase's precedent for preferring real
/// dependencies over mocks wherever the real thing can run under
/// `swift test` (epic-20-implementation.md's own Slice 0 spike;
/// `MermaidWebRendererTests`).
@Suite("D2WebRenderer")
struct D2WebRendererTests {
    private static let context = D2RenderContext.neutralLight

    private static func fence(_ source: String) -> D2Fence {
        D2Fence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func codeBlockStillRendersWithTheReplacementFont() async throws {
        let renderer = D2WebRenderer(poolSize: 1)
        let diagram = try await renderer.render(Self.fence(
            "sample: |go\n  fmt.Println(\"hello\")\n|"
        ), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.svg.contains(".text-mono"))
        #expect(diagram.svg.contains("data:application/font-woff;base64,"))
        #expect(diagram.svg.contains("fmt.<tspan"))
        #expect(diagram.svg.contains(">Println</tspan>"))
        await renderer.shutdown()
    }

    @Test func renderProducesRealSVGForValidSource() async throws {
        let renderer = D2WebRenderer()
        let diagram = try await renderer.render(Self.fence("a -> b -> c"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        // Confirmed by a real Slice 0 spike: D2's native output has no
        // <foreignObject>, which is exactly why RenderedD2Diagram carries
        // no pngData field — this assertion keeps that assumption honest.
        #expect(!diagram.svg.contains("foreignObject"))
        await renderer.shutdown()
    }

    @Test func generatedDefaultsUseTheResolvedMonochromePalette() async throws {
        let renderer = D2WebRenderer()
        let diagram = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        #expect(diagram.svg.contains(".fill-B6{fill:#FFFFFF;}"))
        #expect(diagram.svg.contains(".fill-N1{fill:#1A1A1A;}"))
        #expect(diagram.svg.contains(".stroke-B1{stroke:#1A1A1A;}"))
        #expect(diagram.svg.range(
            of: #"<rect[^>]*class=" stroke-B1 fill-B6""#, options: .regularExpression
        ) != nil)
        #expect(diagram.svg.range(
            of: #"<text[^>]*class="text-bold fill-N1"[^>]*>a</text>"#, options: .regularExpression
        ) != nil)
        #expect(diagram.svg.range(
            of: #"<path[^>]*class="connection stroke-B1""#, options: .regularExpression
        ) != nil)
        for generatedColor in ["#4A6FF3", "#0D32B2", "#F7F8FE"] {
            #expect(!diagram.svg.localizedCaseInsensitiveContains(generatedColor))
        }
        await renderer.shutdown()
    }

    @Test func bundledBackgroundDecodesWhiteInAppKit() async throws {
        let renderer = D2WebRenderer()
        let diagram = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        let image = try #require(NSImage(data: Data(diagram.svg.utf8)))
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        let corner = try #require(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        #expect(corner.redComponent > 0.95)
        #expect(corner.greenComponent > 0.95)
        #expect(corner.blueComponent > 0.95)
        await renderer.shutdown()
    }

    @Test func opaqueCanvasPreservesAuthoredDiagramColor() async throws {
        let renderer = D2WebRenderer()
        let dark = D2RenderContext(
            foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
            backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
        )
        let diagram = try await renderer.render(
            Self.fence("a: { style.fill: \"#123456\" }\na -> b: edge label"), context: dark
        )
        #expect(diagram.svg.range(
            of: ##"<svg[^>]*><rect[^>]*fill="#000000""##,
            options: [.regularExpression]
        ) != nil)
        #expect(diagram.svg.localizedCaseInsensitiveContains("#123456"))
        #expect(diagram.svg.contains("edge label"))
        await renderer.shutdown()
    }

    @Test func darkScreenDefaultsUsePreviewTextStrokeAndCanvas() async throws {
        let renderer = D2WebRenderer(poolSize: 1)
        let dark = D2RenderContext(
            foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
            backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
        )
        let diagram = try await renderer.render(Self.fence("a -> b: edge"), context: dark)
        #expect(diagram.svg.contains(".fill-N1{fill:#FFFFFF;}"))
        #expect(diagram.svg.contains(".fill-N2{fill:#FFFFFF;}"))
        #expect(diagram.svg.contains(".stroke-B1{stroke:#FFFFFF;}"))
        #expect(diagram.svg.range(of: ##"<text[^>]*fill="#FFFFFF""##, options: .regularExpression) != nil)
        #expect(diagram.svg.range(of: ##"<path[^>]*stroke="#FFFFFF""##, options: .regularExpression) != nil)
        #expect(diagram.svg.contains(##"fill="#000000""##))
        let authored = try await renderer.render(Self.fence(
            "style.fill: \"#654321\"\na: {style.fill: \"#123456\"; style.stroke: black; style.font-color: black}"
        ), context: dark)
        #expect(authored.svg.localizedCaseInsensitiveContains("#654321"))
        #expect(authored.svg.localizedCaseInsensitiveContains("#123456"))
        #expect(authored.svg.contains("stroke=\"black\""))
        #expect(authored.svg.contains("fill=\"black\""))
        await renderer.shutdown()
    }

    @Test func renderThrowsInvalidSyntaxForMalformedSource() async throws {
        let renderer = D2WebRenderer()
        await #expect(throws: D2RenderError.self) {
            _ = try await renderer.render(Self.fence("{{{ not valid d2 ]["), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRecoversAfterAPriorFailureOnTheSamePooledPage() async throws {
        let renderer = D2WebRenderer(poolSize: 1)
        await #expect(throws: D2RenderError.self) {
            _ = try await renderer.render(Self.fence("{{{ not valid d2 ]["), context: Self.context)
        }
        let diagram = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    @Test func renderTimesOutWhenTheBudgetIsSetBelowRealRenderTime() async throws {
        let renderer = D2WebRenderer(timeout: .milliseconds(1))
        await #expect(throws: D2RenderError.timedOut) {
            _ = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRejectsOutputAboveTheConfiguredSizeCeiling() async throws {
        let renderer = D2WebRenderer(maxOutputBytes: 10)
        await #expect(throws: D2RenderError.self) {
            _ = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func concurrentRendersAllCompleteAcrossABoundedPool() async throws {
        // Six requests share two slots: the last pair may queue behind two
        // legal five-second render windows. The separate admission budget
        // must cover that queue without extending each script's deadline.
        let renderer = D2WebRenderer(poolSize: 2)
        try await withThrowingTaskGroup(of: RenderedD2Diagram.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    try await renderer.render(Self.fence("a\(index) -> b\(index)"), context: Self.context)
                }
            }
            var count = 0
            for try await diagram in group {
                #expect(diagram.svg.contains("<svg"))
                count += 1
            }
            #expect(count == 6)
        }
        await renderer.shutdown()
    }

    @Test func rendererReinitializesLazilyAfterShutdown() async throws {
        let renderer = D2WebRenderer(poolSize: 1)
        _ = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        await renderer.shutdown()
        let diagram = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    /// Adversarial corpus (epic-21-implementation.md Slice 5, mirroring
    /// epic-20-implementation.md §15): a genuinely larger, more realistic
    /// diagram — not just a two-node smoke test — to catch problems that
    /// only appear with real layout complexity (long render time,
    /// degenerate output). Containers, multiple shapes, and styled
    /// connections.
    @Test func renderHandlesAModeratelyComplexDiagramWithinTheDefaultTimeout() async throws {
        let renderer = D2WebRenderer()
        let source = """
        classes: {
          service: { style.fill: "#e3f2fd" }
        }
        client: Client
        gateway: API Gateway
        auth: Auth Service { class: service }
        orders: Orders Service { class: service }
        db: Database { shape: cylinder }
        client -> gateway: request
        gateway -> auth: verify token
        gateway -> orders: forward
        orders -> db: read/write
        auth -> db: lookup user
        gateway -> client: response {
          style.stroke-dash: 3
        }
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        await renderer.shutdown()
    }

    /// Adversarial corpus: whitespace-only source must fail (or otherwise
    /// resolve) the same safe, diagnosable way every time — never hang,
    /// never crash. D2 tolerates an empty document as a real, deliberate
    /// language feature (an empty diagram is valid D2), so this asserts
    /// the safe-completion contract rather than assuming an error, unlike
    /// Mermaid/Graphviz which both require a real keyword to parse.
    @Test func renderCompletesSafelyOnWhitespaceOnlySource() async throws {
        let renderer = D2WebRenderer()
        let diagram = try await renderer.render(Self.fence("   \n\n   "), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }
}
