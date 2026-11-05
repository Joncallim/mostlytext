import AppKit
import CoreGraphics
import Foundation
import Math
import SwiftUI
@_spi(Textual) import SwiftUIMath

/// Rasterizes shared validated bodies through SwiftUIMath and ImageRenderer.
/// The typed-body extension checks geometry, pixel and PNG limits before output.
/// Original String/span factories remain available for compatibility; production
/// Preview and Export consume parser-admitted bodies rather than their old
/// zero-size validity heuristic. SwiftUIMath.Math is separate from the local
/// renderer-neutral Math module.
@MainActor
public enum MathImageRenderer {
    /// Chosen for legible on-screen/print quality without producing
    /// unreasonably large `data:` URIs (epic-19-implementation.md §11).
    /// `nonisolated`: a plain constant, safe to read from any context
    /// without hopping onto the main actor just to build an
    /// `ExportMathRenderContext` (`MathExportRegistry.swift`, app target).
    public nonisolated static let standardScale: CGFloat = 3

    /// Legacy synchronous String/span metrics retain their existing font.
    /// The production typed API supplies the same font after body admission.
    private nonisolated static let font = SwiftUIMath.Math.Font(name: .latinModern, size: 18)

    private nonisolated static func style(for span: MathSpan) -> SwiftUIMath.Math.TypesettingStyle {
        span.style == .inline ? .text : .display
    }

    private nonisolated static func bounds(for span: MathSpan) -> SwiftUIMath.Math.TypographicBounds {
        SwiftUIMath.Math.typographicBounds(
            for: span.latex, fitting: ProposedViewSize(width: nil, height: nil), font: font, style: style(for: span)
        )
    }

    /// Legacy String/span renderability check. This does not classify parser
    /// errors or distinguish valid empty geometry; production uses typed
    /// evaluation and MathRenderError.noVisibleOutput instead.
    public nonisolated static func isRenderable(_ span: MathSpan) -> Bool {
        let size = bounds(for: span).size
        return size.width > 0 && size.height > 0
    }

    /// Matches the `MathImageRendering` typealias (`Math` target) so this
    /// can be passed directly as `MathContribution`'s injected renderer;
    /// being `@MainActor`-isolated while that typealias is not is fine —
    /// Swift hops onto the main actor when this is called through the
    /// closure value, matching how `ImageRenderer`/AppKit work already
    /// requires main-actor affinity elsewhere in this app (epic-12
    /// §3.7's own "only UI snapshot/save-panel state and WebKit/AppKit/
    /// PDFKit work are main-actor" rule).
    ///
    /// Synchronous and CPU-bound, with no internal cancellation
    /// checkpoints — once called, one equation's layout/PNG encoding
    /// always runs to completion. `MathContribution.run` can only check
    /// cancellation BETWEEN spans, not interrupt one already in progress
    /// (an accepted, bounded limitation — see
    /// `MathContributionTests.runStopsBetweenSpansWhenTheAmbientTaskIsCancelled`'s
    /// own doc comment).
    public static func render(span: MathSpan, context: ExportMathRenderContext) throws -> RenderedMathImage {
        let style = Self.style(for: span)
        let bounds = Self.bounds(for: span)
        guard bounds.size.width > 0, bounds.size.height > 0 else {
            throw MathRenderError.couldNotTypeset
        }

        let color = Color(
            red: context.foregroundRed, green: context.foregroundGreen, blue: context.foregroundBlue
        )
        let view = SwiftUIMath.Math(span.latex)
            .mathFont(font)
            .mathTypesettingStyle(style)
            .foregroundStyle(color)
            .frame(width: bounds.size.width, height: bounds.size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = context.pixelScale

        guard let cgImage = renderer.cgImage else {
            throw MathRenderError.couldNotTypeset
        }
        guard let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw MathRenderError.couldNotTypeset
        }
        return RenderedMathImage(
            pngData: pngData,
            logicalWidth: Double(bounds.size.width),
            logicalHeight: Double(bounds.size.height)
        )
    }
}
