import Foundation

/// The cursor + line bookkeeping shared by the JSON grammar functions.
///
/// `JSONScanner` owns the immutable UTF-16 unit snapshot and the position
/// cursor; the value grammar (`parseValue`, objects, arrays, numbers,
/// literals) lives in `JSONScanner+Values.swift` and the string grammar in
/// `JSONScanner+Strings.swift`. One stateful machine split across three files
/// keeps every file under the length budget without obscuring the single
/// recursive-descent pass.
struct JSONScanner {
    let units: [UInt16]
    /// Offset of the first unit of every LF, CRLF or CR-delimited physical
    /// line, built once in O(n). Line queries are binary searches, so per-node bookkeeping
    /// never degrades parsing to O(n²).
    let lineStarts: [Int]
    var position = 0
    /// Current container nesting depth, bounded by
    /// `JSONParser.maxNestingDepth` in `parseObject`/`parseArray`.
    var nestingDepth = 0

    init(units: [UInt16]) {
        self.units = units
        var lineStarts = [0]
        for (index, unit) in units.enumerated() {
            switch unit {
            case 0x000A: // LF, including the end of one CRLF pair
                lineStarts.append(index + 1)
            case 0x000D where index + 1 == units.count || units[index + 1] != 0x000A:
                lineStarts.append(index + 1) // A lone CR is a physical line break too.
            default:
                break
            }
        }
        self.lineStarts = lineStarts
    }

    var isAtEnd: Bool {
        position >= units.count
    }

    func peek(_ offset: Int = 0) -> UInt16? {
        let index = position + offset
        guard index >= 0, index < units.count else { return nil }
        return units[index]
    }

    func diagnostic(_ message: String, at offset: Int) -> JSONDiagnostic {
        let lineInfo = line(at: offset)
        return JSONDiagnostic(
            message: message,
            line: lineInfo.line,
            column: offset - lineInfo.start + 1,
            range: offset < units.count ? offset ..< (offset + 1) : nil
        )
    }

    mutating func skipWhitespace() {
        while let unit = peek(), unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D {
            position += 1
        }
    }

    // MARK: Line bookkeeping

    /// 1-based line number and the line's first-unit offset for `offset`.
    func line(at offset: Int) -> (line: Int, start: Int) {
        var low = 0
        var high = lineStarts.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return (best + 1, lineStarts[best])
    }

    func lineNumber(of offset: Int) -> Int {
        line(at: offset).line
    }

    func lineRange(from start: Int, to end: Int) -> ClosedRange<Int> {
        lineNumber(of: start) ... lineNumber(of: max(start, end - 1))
    }
}

/// The outcome of one grammar production: a parsed node or the single
/// diagnostic that stopped the parse.
enum ParseResult {
    case node(JSONNode)
    case diagnostic(JSONDiagnostic)
}

/// The outcome of parsing a quoted string: the decoded value with its UTF-16
/// range, or a diagnostic.
enum StringResult {
    case decoded(String, range: Range<Int>)
    case failed(JSONDiagnostic)
}

extension JSONScanner {
    /// A diagnostic message looked up in this module's own string catalog (`bundle: .module`),
    /// not the app's — see `PackageStringLocalizationTests`.
    func localized(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .module)
    }
}
