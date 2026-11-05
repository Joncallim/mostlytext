import Foundation

enum MathSourceIntervals {
    static func segments(
        units: [UInt16], regions: [Range<Int>], exclusions: [Range<Int>]
    ) throws -> [Range<Int>] {
        let ordered = regions.sorted { $0.lowerBound < $1.lowerBound }
        var previousEnd = 0
        for region in ordered {
            guard valid(region, units: units) else { throw MathSyntaxError.invalidRegion }
            guard region.lowerBound >= previousEnd else { throw MathSyntaxError.overlappingRegions }
            previousEnd = region.upperBound
        }
        let barriers = try mergedExclusions(exclusions, units: units)
        var result: [Range<Int>] = []
        var barrierIndex = 0
        for region in ordered where !region.isEmpty {
            while barrierIndex < barriers.count, barriers[barrierIndex].upperBound <= region.lowerBound {
                barrierIndex += 1
            }
            var cursor = region.lowerBound
            while barrierIndex < barriers.count, barriers[barrierIndex].lowerBound < region.upperBound {
                let barrier = barriers[barrierIndex]
                if barrier.lowerBound > cursor {
                    result.append(cursor ..< barrier.lowerBound)
                }
                cursor = max(cursor, min(barrier.upperBound, region.upperBound))
                if barrier.upperBound > region.upperBound {
                    break
                }
                barrierIndex += 1
            }
            if cursor < region.upperBound {
                result.append(cursor ..< region.upperBound)
            }
        }
        return result
    }

    private static func mergedExclusions(_ ranges: [Range<Int>], units: [UInt16]) throws -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard valid(range, units: units) else { throw MathSyntaxError.invalidExclusion }
            guard !range.isEmpty else { continue }
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func valid(_ range: Range<Int>, units: [UInt16]) -> Bool {
        range.lowerBound >= 0 && range.upperBound <= units.count &&
            scalarBoundary(range.lowerBound, units: units) && scalarBoundary(range.upperBound, units: units)
    }

    private static func scalarBoundary(_ offset: Int, units: [UInt16]) -> Bool {
        guard offset > 0, offset < units.count else { return true }
        return !(0xD800 ... 0xDBFF).contains(units[offset - 1]) || !(0xDC00 ... 0xDFFF).contains(units[offset])
    }
}
