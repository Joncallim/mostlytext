import Foundation

/// Provisional raster safety ceilings; final whole-export calibration is separate.
public struct MathImageBudget: Sendable, Equatable {
    public struct Admission: Sendable, Equatable {
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    public let maximumLogicalDimension: Double
    public let maximumPixelDimension: Int
    public let maximumPixels: Int
    public let maximumPNGBytes: Int

    public static let standard = MathImageBudget(
        maximumLogicalDimension: 4096, maximumPixelDimension: 8192,
        maximumPixels: 16_777_216, maximumPNGBytes: 8 * 1024 * 1024
    )

    public init(maximumLogicalDimension: Double, maximumPixelDimension: Int, maximumPixels: Int, maximumPNGBytes: Int) {
        self.maximumLogicalDimension = maximumLogicalDimension
        self.maximumPixelDimension = maximumPixelDimension
        self.maximumPixels = maximumPixels
        self.maximumPNGBytes = maximumPNGBytes
    }

    /// Admission happens before constructing the raster renderer or its bitmap.
    public func admit(logicalWidth: Double, logicalHeight: Double, pixelScale: Double) throws -> Admission {
        guard maximumLogicalDimension.isFinite, maximumLogicalDimension > 0,
              maximumPixelDimension > 0, maximumPixels > 0, maximumPNGBytes > 0,
              logicalWidth.isFinite, logicalHeight.isFinite, logicalWidth >= 0, logicalHeight >= 0,
              pixelScale.isFinite, pixelScale > 0 else { throw MathRenderError.invalidImageDimensions }
        guard logicalWidth > 0, logicalHeight > 0 else { throw MathRenderError.noVisibleOutput }
        guard logicalWidth <= maximumLogicalDimension, logicalHeight <= maximumLogicalDimension else {
            throw MathRenderError.resourceLimit
        }
        let width = (logicalWidth * pixelScale).rounded(.up)
        let height = (logicalHeight * pixelScale).rounded(.up)
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= Double(maximumPixelDimension), height <= Double(maximumPixelDimension),
              width < Double(Int.max), height < Double(Int.max) else { throw MathRenderError.resourceLimit }
        let admission = Admission(pixelWidth: Int(width), pixelHeight: Int(height))
        try validatePixels(width: admission.pixelWidth, height: admission.pixelHeight)
        return admission
    }

    /// Rechecks actual renderer output before handing a bitmap to the PNG encoder.
    public func validatePixels(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw MathRenderError.invalidImageDimensions }
        guard width <= maximumPixelDimension, height <= maximumPixelDimension,
              maximumPixels > 0, width <= maximumPixels / height else { throw MathRenderError.resourceLimit }
    }

    public func validatePNGByteCount(_ count: Int) throws {
        guard count > 0 else { throw MathRenderError.couldNotTypeset }
        guard maximumPNGBytes > 0, count <= maximumPNGBytes else { throw MathRenderError.resourceLimit }
    }
}
