import Contributions
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import Foundation
import MarkdownEngine
import Math
import MathRendering
import Themes

/// Export registers the same source-owned, bounded math evaluation used by
/// Preview. Native Preview consumes typed attachments rather than HTML results;
/// diagrams retain their dedicated native views and Export-only contributions.
extension ContributionRegistry {
    /// `ExportService`'s own `structural.css` overrides EVERY theme's
    /// foreground/background for `@media print` — "Paper is white. A dark
    /// theme's foreground would print as light text on a white page... so
    /// print gets its own readable palette" (`structural.css`, `@media
    /// print` block). Ordinary themed body text is safe because that CSS
    /// override applies to it live; a math equation is a pre-baked PNG of
    /// fixed pixel colors that CSS cannot recolor after the fact — found
    /// during this epic's own adversarial review (a dark theme's light
    /// foreground, baked into an equation image, would print as
    /// near-invisible light-gray-on-white). `isPrintTarget` therefore
    /// selects the identical fixed color `structural.css` uses for print
    /// (`#1a1a1a`) instead of the live theme's foreground when rendering
    /// for PDF; this constant must stay in sync with that CSS file's own
    /// `--md-foreground` print value.
    private static let printSafeForegroundComponent = 0x1A as Double / 255.0

    static func standardForExport(
        theme: Theme, isPrintTarget: Bool, headingIndex: HeadingAnchorIndex? = nil
    ) -> ContributionRegistry {
        let context = mathRenderContext(theme: theme, isPrintTarget: isPrintTarget)
        let mermaidContext = mermaidRenderContext(theme: theme, isPrintTarget: isPrintTarget)
        let d2Context = d2RenderContext(theme: theme, isPrintTarget: isPrintTarget)
        let graphvizContext = graphvizRenderContext(theme: theme, isPrintTarget: isPrintTarget)
        return ContributionRegistry(contributions: [
            TOCContribution(headingIndex: headingIndex),
            SharedMathContribution(context: context) { body, style, context in
                try await MainActor.run { try MathImageRenderer.render(body: body, style: style, context: context) }
            },
            MermaidContribution(context: mermaidContext, renderer: sharedMermaidRenderer),
            D2Contribution(context: d2Context, renderer: sharedD2Renderer),
            GraphvizContribution(context: graphvizContext, renderer: sharedGraphvizRenderer),
        ])
    }

    /// Split out from `standardForExport` so the color-selection rule
    /// itself is directly unit-testable without inspecting a constructed
    /// `SharedMathContribution`'s private state.
    static func mathRenderContext(theme: Theme, isPrintTarget: Bool) -> ExportMathRenderContext {
        if isPrintTarget {
            return ExportMathRenderContext(
                foregroundRed: printSafeForegroundComponent,
                foregroundGreen: printSafeForegroundComponent,
                foregroundBlue: printSafeForegroundComponent,
                pixelScale: MathImageRenderer.standardScale
            )
        }
        let foreground = theme.chrome.foreground
        return ExportMathRenderContext(
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            pixelScale: MathImageRenderer.standardScale
        )
    }
}
