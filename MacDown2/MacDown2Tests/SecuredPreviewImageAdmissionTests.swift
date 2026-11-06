import AppKit
import ImageIO
@testable import MacDown2
@testable import Preview
import Testing
import UniformTypeIdentifiers

/// Real ImageIO metadata is the admission input; a ledger-only rejection does not prove decode is bounded.
@Suite("Secured Preview ImageIO admission", .serialized)
@MainActor
struct SecuredPreviewImageAdmissionTests {
    @Test(arguments: [(8193, 1), (4096, 4096)])
    func hugePNGDimensionsAreRejectedWithoutRetainingDecodedCapacity(width: Int, height: Int) throws {
        // Real compressed rasters reach ImageIO's metadata reader: one exceeds the axis cap, the other the
        // decoded-byte cap. The small encoded input alone cannot establish safe decoded allocation.
        let bytes = try png(width: width, height: height)
        #expect(bytes.count < PreviewResourceAdmission.resourceLimit)
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == width)
        #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == height)
        let budget = PreviewImageDecodeBudget()
        #expect(throws: PreviewImageLoadError.self) {
            _ = try PreviewImageDecoder.decode(bytes, budget: budget)
        }
        #expect(budget.reservedBytes == 0)
    }

    @Test func realMultipleFrameImageIsRejectedBeforeRasterAllocation() throws {
        let source = try #require(try CGImageSourceCreateWithData(png() as CFData, nil))
        let raster = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            bytes,
            UTType.gif.identifier as CFString,
            2,
            nil
        ))
        CGImageDestinationAddImage(destination, raster, nil)
        CGImageDestinationAddImage(destination, raster, nil)
        #expect(CGImageDestinationFinalize(destination))
        let animated = try #require(CGImageSourceCreateWithData(bytes, nil))
        #expect(CGImageSourceGetCount(animated) == 2)
        let budget = PreviewImageDecodeBudget()
        #expect(throws: PreviewImageLoadError.self) {
            _ = try PreviewImageDecoder.decode(bytes as Data, budget: budget)
        }
        #expect(budget.reservedBytes == 0)
    }

    @Test func ordinaryImageStillDecodesAndItsActualRasterFitsTheReservation() throws {
        let budget = PreviewImageDecodeBudget()
        let decoded = try PreviewImageDecoder.decode(png(), budget: budget)
        #expect(decoded.raster.width == 8)
        #expect(decoded.raster.height == 8)
        #expect(decoded.raster.bytesPerRow * decoded.raster.height <= budget.reservedBytes)
        #expect(budget.reservedBytes == 8 * 8 * 8)
    }

    private func png(width: Int = 8, height: Int = 8) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let storage = try #require(bitmap.bitmapData)
        storage.initialize(repeating: 0, count: bitmap.bytesPerRow * height)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
