import AppKit
import ImageIO
@testable import Preview
import Testing
import UniformTypeIdentifiers

/// Real ImageIO metadata is the admission input; a ledger-only rejection does not prove decode is bounded.
@Suite("Secured Preview ImageIO admission", .serialized)
@MainActor
struct SecuredPreviewImageAdmissionTests {
    @Test func hugePNGDimensionsAreRejectedWithoutRetainingDecodedCapacity() throws {
        var bytes = try png()
        #expect(bytes.count > 33)
        // Preserve a real PNG's compressed payload, but declare an enormous raster in its valid-CRC IHDR.
        let dimension: [UInt8] = [0, 1, 0, 0]
        bytes.replaceSubrange(16 ..< 20, with: dimension)
        bytes.replaceSubrange(20 ..< 24, with: dimension)
        let checksum = crc32(bytes[12 ..< 29])
        bytes.replaceSubrange(29 ..< 33, with: (0 ..< 4).map {
            UInt8(truncatingIfNeeded: checksum >> ((3 - $0) * 8))
        })
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 65536)
        #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 65536)
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

    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func crc32(_ bytes: Data.SubSequence) -> UInt32 {
        var checksum = UInt32.max
        for byte in bytes {
            checksum ^= UInt32(byte)
            for _ in 0 ..< 8 {
                checksum = (checksum >> 1) ^ (checksum & 1 == 0 ? 0 : 0xEDB8_8320)
            }
        }
        return ~checksum
    }
}
