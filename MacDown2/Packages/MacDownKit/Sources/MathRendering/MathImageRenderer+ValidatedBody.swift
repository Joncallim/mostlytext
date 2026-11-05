import AppKit
import Foundation
import Math
import MathSyntax
import SwiftUI
@_spi(Textual) import SwiftUIMath

public extension MathImageRenderer {
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
        let bounds = SwiftUIMath.Math.typographicBounds(
            for: body, fitting: .unspecified, font: font, style: typesettingStyle
        )
        _ = try budget.admit(logicalWidth: Double(bounds.size.width), logicalHeight: Double(bounds.size.height),
                             pixelScale: Double(context.pixelScale))
        try Task.checkCancellation()
        let view = SwiftUIMath.Math(body)
            .mathFont(font)
            .mathTypesettingStyle(typesettingStyle)
            .foregroundStyle(Color(
                red: context.foregroundRed,
                green: context.foregroundGreen,
                blue: context.foregroundBlue
            ))
            .frame(width: bounds.size.width, height: bounds.size.height)
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
            logicalWidth: Double(bounds.size.width),
            logicalHeight: Double(bounds.size.height)
        )
    }
}
