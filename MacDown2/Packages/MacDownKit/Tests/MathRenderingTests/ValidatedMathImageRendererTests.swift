import AppKit
import Foundation
import Math
import MathRendering
import MathSyntax
import SwiftUIMath
import Testing

@MainActor
@Suite("Typed body raster admission", .serialized)
struct ValidatedMathImageRendererTests {
    private let context = ExportMathRenderContext(
        foregroundRed: 0.1,
        foregroundGreen: 0.1,
        foregroundBlue: 0.1,
        pixelScale: 3
    )

    private func body(_ source: String) throws -> SwiftUIMath.Math.ValidatedBody {
        let result = try SwiftUIMath.Math.validateBody(source, limits: .init(maximumUTF16Length: 16384,
                                                                             maximumDepth: 64,
                                                                             maximumParserSteps: 65536))
        guard case let .valid(body) = result else { throw MathRenderError.couldNotTypeset }
        return body
    }

    @Test(arguments: [MathDelimiterStyle.inline, .display])
    func actualTypedBodyProducesBoundedDecodablePixels(_ style: MathDelimiterStyle) throws {
        let image = try MathImageRenderer.render(body: body("\\frac{1}{2}+x"), style: style, context: context)
        let bitmap = try #require(NSBitmapImageRep(data: image.pngData))
        try MathImageBudget.standard.validatePixels(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        try MathImageBudget.standard.validatePNGByteCount(image.pngData.count)
        #expect(image.logicalWidth > 0 && image.logicalHeight > 0)
        #expect(abs(Double(bitmap.pixelsWide) - image.logicalWidth * 3) <= 2)
        #expect(abs(Double(bitmap.pixelsHigh) - image.logicalHeight * 3) <= 2)
    }

    @Test(arguments: ["", "% comment", "\\ "])
    func acceptedZeroInkOutputRetainsASeparateNonMalformedState(_ source: String) throws {
        let validated = try body(source)
        #expect(throws: MathRenderError.noVisibleOutput) {
            try MathImageRenderer.render(body: validated, style: .inline, context: context)
        }
    }

    @Test func tightGeometryAndPNGCeilingsRejectTheActualRenderer() throws {
        let validated = try body("x+y")
        let geometry = MathImageBudget(
            maximumLogicalDimension: 1,
            maximumPixelDimension: 1,
            maximumPixels: 1,
            maximumPNGBytes: 1
        )
        #expect(throws: MathRenderError.resourceLimit) {
            try MathImageRenderer.render(body: validated, style: .inline, context: context, budget: geometry)
        }
        let standard = MathImageBudget.standard
        let bytes = MathImageBudget(maximumLogicalDimension: standard.maximumLogicalDimension,
                                    maximumPixelDimension: standard.maximumPixelDimension,
                                    maximumPixels: standard.maximumPixels,
                                    maximumPNGBytes: 1)
        #expect(throws: MathRenderError.resourceLimit) {
            try MathImageRenderer.render(body: validated, style: .inline, context: context, budget: bytes)
        }
    }

    @Test func invalidCallerColorAndScaleFailBeforeDrawing() throws {
        let validated = try body("x")
        for context in [
            ExportMathRenderContext(foregroundRed: .nan, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 3),
            .init(foregroundRed: 2, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 3),
            .init(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: .infinity),
            .init(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: -1),
        ] {
            #expect(throws: MathRenderError.invalidImageDimensions) {
                try MathImageRenderer.render(body: validated, style: .inline, context: context)
            }
        }
    }
}
