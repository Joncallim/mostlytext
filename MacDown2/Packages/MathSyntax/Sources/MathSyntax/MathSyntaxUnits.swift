import Foundation

enum MathSyntaxUnits {
    static func scalar(at offset: Int, in units: [UInt16], before end: Int) -> Unicode.Scalar? {
        guard offset < end else { return nil }
        let unit = units[offset]
        if (0xD800 ... 0xDBFF).contains(unit), offset + 1 < end {
            let low = units[offset + 1]
            if (0xDC00 ... 0xDFFF).contains(low) {
                return Unicode.Scalar(0x10000 + (UInt32(unit) - 0xD800) * 0x400 + UInt32(low) - 0xDC00)
            }
        }
        return Unicode.Scalar(unit)
    }

    static func scalar(before offset: Int, in units: [UInt16], after start: Int) -> Unicode.Scalar? {
        guard offset > start else { return nil }
        let last = units[offset - 1]
        let index = (0xDC00 ... 0xDFFF).contains(last) && offset - start >= 2 ? offset - 2 : offset - 1
        return scalar(at: index, in: units, before: offset)
    }

    static func whitespace(_ scalar: Unicode.Scalar?) -> Bool {
        scalar.map(CharacterSet.whitespacesAndNewlines.contains) ?? false
    }

    static func digit(_ scalar: Unicode.Scalar?) -> Bool {
        scalar.map(CharacterSet.decimalDigits.contains) ?? false
    }

    static func terminatorLength(at offset: Int, in units: [UInt16], before end: Int) -> Int {
        guard offset < end else { return 0 }
        if units[offset] == 10 {
            return 1
        }
        guard units[offset] == 13 else { return 0 }
        return offset + 1 < end && units[offset + 1] == 10 ? 2 : 1
    }

    static func blankLine(at offset: Int, in units: [UInt16], before end: Int) -> Bool {
        let length = terminatorLength(at: offset, in: units, before: end)
        guard length > 0 else { return false }
        var cursor = offset + length
        while cursor < end, units[cursor] == 32 || units[cursor] == 9 {
            cursor += 1
        }
        return terminatorLength(at: cursor, in: units, before: end) > 0
    }
}
