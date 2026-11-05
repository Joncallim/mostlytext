import AppKit
import Foundation
import Math
import MathSyntax
import SwiftUI
@_spi(Textual) import SwiftUIMath

public extension MathImageRenderer {
    /// Preview uses the same admitted raw-body geometry as Export before it
    /// chooses a native attachment. Zero output remains valid source fallback.
    static func admittedSize(
        body: SwiftUIMath.Math.ValidatedBody, style: MathDelimiterStyle,
        pixelScale: Double = 1, budget: MathImageBudget = .standard
    ) throws -> CGSize {
        try Task.checkCancellation()
        let bounds = SwiftUIMath.Math.typographicBounds(
            for: body, fitting: .unspecified, font: .init(name: .latinModern, size: 18),
            style: style == .inline ? .text : .display
        )
        _ = try budget.admit(logicalWidth: Double(bounds.size.width), logicalHeight: Double(bounds.size.height),
                             pixelScale: pixelScale)
        try Task.checkCancellation()
        return bounds.size
    }

    /// Renders the exact parser-admitted body with bounds checked before raster allocation.
    static func render(
        body: SwiftUIMath.Math.ValidatedBody, style: MathDelimiterStyle,
        context: ExportMathRenderContext, budget: MathImageBudget = .standard
    ) throws -> RenderedMathImage {
        try Task.checkCancellation()
        guard [context.foregroundRed, context.foregroundGreen, context.foregroundBlue].allSatisfy({
            $0.isFinite && (0 ... 1).contains($0)
        }), context.pixelScale.isFinite, context.pixelScale > 0 else { throw MathRenderError.invalidImageDimensions }
        let font = SwiftUIMath.Math.Font(name: .latinModern, size: 18)
        let typesettingStyle: SwiftUIMath.Math.TypesettingStyle = style == .inline ? .text : .display
        let size = try admittedSize(
            body: body, style: style, pixelScale: Double(context.pixelScale), budget: budget
        )
        try Task.checkCancellation()
        let view = SwiftUIMath.Math(body)
            .mathFont(font)
            .mathTypesettingStyle(typesettingStyle)
            .foregroundStyle(Color(
                red: context.foregroundRed,
                green: context.foregroundGreen,
                blue: context.foregroundBlue
            ))
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = context.pixelScale
        guard let image = renderer.cgImage else { throw MathRenderError.couldNotTypeset }
        try budget.validatePixels(width: image.width, height: image.height)
        try Task.checkCancellation()
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw MathRenderError.couldNotTypeset
        }
        try budget.validatePNGByteCount(png.count)
        try Task.checkCancellation()
        return RenderedMathImage(
            pngData: png,
            logicalWidth: Double(size.width),
            logicalHeight: Double(size.height)
        )
    }
}
