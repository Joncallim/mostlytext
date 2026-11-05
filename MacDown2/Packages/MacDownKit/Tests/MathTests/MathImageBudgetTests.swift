import Foundation
@testable import Math
import Testing

@Suite("Math raster allocation admission")
struct MathImageBudgetTests {
    private let budget = MathImageBudget(maximumLogicalDimension: 10, maximumPixelDimension: 20,
                                         maximumPixels: 200, maximumPNGBytes: 20)

    @Test func logicalPhysicalProductAndPNGCeilingsIncludeTheirExactBoundary() throws {
        let admitted = try budget.admit(logicalWidth: 10, logicalHeight: 5, pixelScale: 2)
        #expect(admitted.pixelWidth == 20 && admitted.pixelHeight == 10)
        try budget.validatePixels(width: 20, height: 10)
        try budget.validatePNGByteCount(20)
        #expect(throws: MathRenderError.resourceLimit) { try budget.admit(
            logicalWidth: 10.001,
            logicalHeight: 5,
            pixelScale: 2
        ) }
        #expect(throws: MathRenderError.resourceLimit) { try budget.admit(
            logicalWidth: 10,
            logicalHeight: 5.001,
            pixelScale: 2
        ) }
        #expect(throws: MathRenderError.resourceLimit) { try budget.validatePixels(width: 21, height: 1) }
        #expect(throws: MathRenderError.resourceLimit) { try budget.validatePixels(width: 20, height: 11) }
        #expect(throws: MathRenderError.resourceLimit) { try budget.validatePNGByteCount(21) }
    }

    @Test func fractionalDimensionsRoundUpBeforeCheckingThePhysicalProduct() throws {
        let admitted = try budget.admit(logicalWidth: 9.51, logicalHeight: 4.51, pixelScale: 2)
        #expect(admitted.pixelWidth == 20 && admitted.pixelHeight == 10)
        #expect(throws: MathRenderError.resourceLimit) { try budget.admit(
            logicalWidth: 9.51,
            logicalHeight: 5.01,
            pixelScale: 2
        ) }
    }

    @Test func zeroGeometryIsNotAParserValidityDecision() {
        for (width, height) in [(0.0, 1.0), (1.0, 0.0), (0.0, 0.0)] {
            #expect(throws: MathRenderError.noVisibleOutput) { try budget.admit(
                logicalWidth: width,
                logicalHeight: height,
                pixelScale: 1
            ) }
        }
        #expect(throws: MathRenderError.invalidImageDimensions) { try budget.admit(
            logicalWidth: 0,
            logicalHeight: .infinity,
            pixelScale: 1
        ) }
        #expect(throws: MathRenderError.couldNotTypeset) { try budget.validatePNGByteCount(0) }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func invalidGeometryAndScaleCannotReachIntegerConversion(_ value: Double) {
        #expect(throws: MathRenderError.invalidImageDimensions) { try budget.admit(
            logicalWidth: value,
            logicalHeight: 1,
            pixelScale: 1
        ) }
        #expect(throws: MathRenderError.invalidImageDimensions) { try budget.admit(
            logicalWidth: 1,
            logicalHeight: value,
            pixelScale: 1
        ) }
        #expect(throws: MathRenderError.invalidImageDimensions) { try budget.admit(
            logicalWidth: 1,
            logicalHeight: 1,
            pixelScale: value
        ) }
        #expect(throws: MathRenderError.invalidImageDimensions) { try budget.admit(
            logicalWidth: 1,
            logicalHeight: 1,
            pixelScale: 0
        ) }
    }

    @Test func integerLimitsAndFloatingOverflowNeverTrapOrAllocate() {
        let enormous = MathImageBudget(maximumLogicalDimension: .greatestFiniteMagnitude,
                                       maximumPixelDimension: Int.max, maximumPixels: Int.max, maximumPNGBytes: 1)
        #expect(throws: MathRenderError.resourceLimit) { try enormous.admit(
            logicalWidth: Double(Int.max),
            logicalHeight: 1,
            pixelScale: 1
        ) }
        #expect(throws: MathRenderError.resourceLimit) { try enormous.admit(
            logicalWidth: .greatestFiniteMagnitude,
            logicalHeight: 1,
            pixelScale: 2
        ) }
        #expect(throws: MathRenderError.resourceLimit) { try enormous.validatePixels(width: Int.max, height: Int.max) }
        #expect(throws: MathRenderError.invalidImageDimensions) {
            try enormous.validatePixels(width: Int.min, height: 1)
        }
        #expect(throws: MathRenderError.resourceLimit) { try MathImageBudget.standard.validatePNGByteCount(Int.max) }
    }

    @Test func invalidBudgetConfigurationFailsClosed() {
        let configurations = [
            MathImageBudget(
                maximumLogicalDimension: .nan,
                maximumPixelDimension: 20,
                maximumPixels: 200,
                maximumPNGBytes: 20
            ),
            .init(maximumLogicalDimension: 0, maximumPixelDimension: 20, maximumPixels: 200, maximumPNGBytes: 20),
            .init(maximumLogicalDimension: 10, maximumPixelDimension: 0, maximumPixels: 200, maximumPNGBytes: 20),
            .init(maximumLogicalDimension: 10, maximumPixelDimension: 20, maximumPixels: 0, maximumPNGBytes: 20),
            .init(maximumLogicalDimension: 10, maximumPixelDimension: 20, maximumPixels: 200, maximumPNGBytes: 0),
        ]
        for budget in configurations {
            #expect(throws: MathRenderError.invalidImageDimensions) { try budget.admit(
                logicalWidth: 1,
                logicalHeight: 1,
                pixelScale: 1
            ) }
        }
    }
}
