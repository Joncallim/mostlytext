import Foundation
@testable import JSONSupport
import Testing

/// EPIC-11 §3.3 — JSON diagnostics: stable values, one diagnostic per
/// document, exact line/column/range, duplicate-key rejection.
@Suite("JSONDiagnostics")
struct JSONDiagnosticsTests {
    @Test func emptyInputReportsLineOneColumnOne() {
        let outcome = JSONParser.parse("")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 1)
        #expect(diagnostic.range == nil)
        #expect(diagnostic.message.contains("Empty input"))
    }

    @Test func whitespaceOnlyInputIsEmpty() {
        let outcome = JSONParser.parse("  \n\t ")
        guard case .invalid = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
    }

    @Test func trailingContentAfterRootValueIsRejected() {
        let outcome = JSONParser.parse("{} extra")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        // '{' unit 0, '}' unit 1, ' ' unit 2, 'e' unit 3 → column 4.
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 4)
        #expect(diagnostic.message.contains("Unexpected content"))
    }

    @Test func missingColonReportsPosition() {
        let outcome = JSONParser.parse("{\"a\" 1}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.line == 1)
        #expect(diagnostic.message.contains("':'"))
    }

    @Test func missingCommaInObjectIsRejected() {
        let outcome = JSONParser.parse("{\"a\":1 \"b\":2}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("',' or '}'"))
    }

    @Test func unterminatedStringIsRejected() {
        let outcome = JSONParser.parse("{\"a\":\"unterminated}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("Unterminated string"))
    }

    @Test func invalidEscapeIsRejected() {
        let outcome = JSONParser.parse("\"\\q\"")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("Invalid escape"))
    }

    @Test func invalidNumberFormsAreRejected() {
        for invalid in ["01", "1.", ".5", "-", "1e", "1e+", "1.2.3", "+1"] {
            let outcome = JSONParser.parse(invalid)
            guard case let .invalid(diagnostic) = outcome else {
                Issue.record("Expected invalid outcome for '\(invalid)'")
                continue
            }
            // The first invalid construct may surface as a number error, an
            // unexpected character, or trailing content — all reject.
            let message = diagnostic.message
            #expect(
                message.contains("Invalid number")
                    || message.contains("Unexpected content")
                    || message.contains("Unexpected character"),
                "for '\(invalid)': \(message)"
            )
        }
    }

    @Test func invalidLiteralIsRejected() {
        let outcome = JSONParser.parse("tru")
        guard case .invalid = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
    }

    @Test func duplicateKeysAreRejectedWithStableDiagnostic() {
        let outcome = JSONParser.parse("{\"a\":1,\"b\":2,\"a\":3}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("Duplicate object key 'a'"))
        // The duplicate key starts after `{"a":1,"b":2,` → unit 13 → column 14.
        #expect(diagnostic.line == 1)
        #expect(diagnostic.column == 14)
    }

    @Test func duplicateKeysAtNestedLevelAreRejected() {
        let outcome = JSONParser.parse("{\"o\":{\"x\":1,\"x\":2}}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("Duplicate object key 'x'"))
    }

    @Test func nestedDuplicateKeyMentionsFirstDefinitionLine() {
        let outcome = JSONParser.parse("{\n  \"a\": 1,\n  \"a\": 2\n}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.line == 3)
        #expect(diagnostic.message.contains("first defined at line 2"))
    }

    @Test func errorLineAndColumnAcrossMultipleLines() {
        // Line 3, column 3 (after `  ` indentation).
        let outcome = JSONParser.parse("{\n  \"a\": 1,\n  x\n}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.line == 3)
        #expect(diagnostic.column == 3)
    }

    @Test func tabsAreWhitespaceAndColumnsCountUTF16Units() {
        let outcome = JSONParser.parse("{\t\"a\":\t1,\t\"a\":\t2}")
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        // { tab " a " : tab 1 , tab " → duplicate key 'a' at unit 10 → col 11.
        #expect(diagnostic.column == 11)
    }

    @Test func topLevelScalarsAreValidDocuments() {
        #expect(valid("5"))
        #expect(valid("-1.5e3"))
        #expect(valid("\"hello\""))
        #expect(valid("true"))
        #expect(valid("null"))
    }

    @Test func deepAndNestedStructuresAreValid() {
        #expect(valid("[[[[[]]]]]"))
        #expect(valid("{\"a\":{\"b\":{\"c\":[1,2,{\"d\":null}]}}}"))
    }

    @Test func validEscapesRoundTrip() {
        guard case let .valid(node) = JSONParser.parse("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\\u00e9\"") else {
            Issue.record("Expected valid outcome")
            return
        }
        guard case let .string(value) = node.value else {
            Issue.record("Expected string node")
            return
        }
        #expect(value == "\"\\/\u{08}\u{0C}\n\r\tAé")
    }

    @Test func surrogatePairEscapeDecodesToAstralScalar() {
        guard case let .valid(node) = JSONParser.parse("\"\\ud83d\\ude00\"") else {
            Issue.record("Expected valid outcome")
            return
        }
        guard case let .string(value) = node.value else {
            Issue.record("Expected string node")
            return
        }
        #expect(value == "😀")
    }

    @Test func unpairedSurrogateEscapeIsRejected() {
        #expect(invalid("\"\\ud83d\""))
        #expect(invalid("\"\\ude00\""))
    }

    @Test func unescapedControlCharacterInStringIsRejected() {
        let text = "\"a\u{01}b\""
        guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("control character"))
    }

    @Test func leadingZeroNumberIsRejected() {
        #expect(invalid("{\"a\": 01}"))
    }

    @Test func validNumbersParse() {
        #expect(valid("0"))
        #expect(valid("-0"))
        #expect(valid("123456789"))
        #expect(valid("0.5"))
        #expect(valid("1e10"))
        #expect(valid("1E-10"))
        #expect(valid("1.5e+3"))
    }

    private func valid(_ text: String) -> Bool {
        if case .valid = JSONParser.parse(text) {
            return true
        }
        return false
    }

    private func invalid(_ text: String) -> Bool {
        if case .invalid = JSONParser.parse(text) {
            return true
        }
        return false
    }
}

/// EPIC-11 §3.3/§3.4 — UTF-16 coordinates: astral scalars, combining marks,
/// and LF, CRLF and CR boundaries must produce exact line/column/range values.
@Suite("JSONDiagnosticUTF16Coordinates")
struct JSONDiagnosticUTF16CoordinateTests {
    @Test func astralScalarInKeyShiftsUTF16Offsets() {
        // '😀' is 2 UTF-16 units. Duplicate key 'a' at unit 14 → column 15.
        let text = "{\"😀\":1,\"a\":2,\"a\":3}"
        guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.column == 15)
        #expect(diagnostic.range == 14 ..< 15)
    }

    @Test func combiningMarksCountPerUTF16Unit() {
        // 'e\u{301}' is 2 UTF-16 units in a 1-unit-wide string slot.
        let text = "{\"e\u{301}\":1,\"a\":2,\"a\":3}"
        guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
            Issue.record("Expected invalid outcome")
            return
        }
        // { " e ́ " : 1 , " a " : 2 , " → duplicate 'a' at unit 14 → col 15.
        #expect(diagnostic.column == 15)
        #expect(diagnostic.range == 14 ..< 15)
    }

    @Test func crlfLineBoundariesCountTheCRInThePhysicalLine() {
        // "{\r\n  \"a\": 1,\r\n  x\r\n}"
        let text = "{\r\n  \"a\": 1,\r\n  x\r\n}"
        guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.line == 3)
        // Line 3 is `  x\r` → 'x' at column 3.
        #expect(diagnostic.column == 3)
    }

    @Test func carriageReturnOnlyAndMixedBreaksLocateTheInvalidUnit() {
        for text in ["{\r  \"a\": 1,\r  x\r}", "{\r\n  \"a\": 1,\r  x\n}"] {
            guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
                Issue.record("Expected invalid outcome")
                continue
            }
            #expect(diagnostic.line == 3)
            #expect(diagnostic.column == 3)
            let expected = (text as NSString).range(of: "x").location
            #expect(diagnostic.range == expected ..< (expected + 1))
        }
        guard case let .invalid(diagnostic) = JSONParser.parse("{\r") else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.line == 2)
        #expect(diagnostic.column == 1)
        #expect(diagnostic.range == nil)
    }

    @Test func astralScalarValueRangeSpansTwoUnits() {
        let text = "[\"😀\"]"
        guard case let .valid(node) = JSONParser.parse(text) else {
            Issue.record("Expected valid outcome")
            return
        }
        guard case let .array(elements) = node.value, let element = elements.first else {
            Issue.record("Expected array with one element")
            return
        }
        // [ " 😀 " ] → string spans units 1...4 (quote, 2 surrogate units, quote).
        #expect(element.sourceRange == 1 ..< 5)
    }

    @Test func combiningMarkRangeWithinString() {
        let text = "[\"e\u{301}\"]"
        guard case let .valid(node) = JSONParser.parse(text) else {
            Issue.record("Expected valid outcome")
            return
        }
        guard case let .array(elements) = node.value, let element = elements.first else {
            Issue.record("Expected array with one element")
            return
        }
        #expect(element.sourceRange == 1 ..< 5) // "e + combining + "
    }

    @Test func diagnosticRangeMarksTheOffendingUnit() {
        let text = "{\"a\": trux}"
        guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
            Issue.record("Expected invalid outcome")
            return
        }
        // 't' at unit 6.
        #expect(diagnostic.range == 6 ..< 7)
    }

    // MARK: Depth policy (EPIC-11 §3.4)

    @Test func documentAtTheNestingLimitIsValid() {
        let depth = JSONParser.maxNestingDepth
        let atLimit = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
        guard case .valid = JSONParser.parse(atLimit) else {
            Issue.record("Expected a document at the nesting limit to be valid")
            return
        }
        // The full pipeline (outline + format) must also survive the limit
        // on a test-runner thread: a depth policy that only protects the
        // parser would still crash the outline builder or the formatter.
        guard case .valid = JSONOutlineBuilder.outline(atLimit) else {
            Issue.record("Expected the outline at the nesting limit to be valid")
            return
        }
        guard case .formatted = JSONFormatter.format(atLimit) else {
            Issue.record("Expected formatting at the nesting limit to succeed")
            return
        }
    }

    @Test func objectNestingAtTheLimitSurvivesTheFullPipeline() {
        // Object nesting is the worst case for stack usage (larger frames
        // than arrays); the analysis path runs outline + format over any
        // valid document, so the limit must hold for objects end to end.
        let depth = JSONParser.maxNestingDepth
        var text = "0"
        for _ in 0 ..< depth {
            text = "{\"k\":\(text)}"
        }
        guard case .valid = JSONOutlineBuilder.outline(text) else {
            Issue.record("Expected the object outline at the nesting limit to be valid")
            return
        }
        guard case .formatted = JSONFormatter.format(text) else {
            Issue.record("Expected object formatting at the nesting limit to succeed")
            return
        }
    }

    @Test func documentBeyondTheNestingLimitIsRejectedWithDiagnostic() {
        let depth = JSONParser.maxNestingDepth
        let tooDeep = String(repeating: "[", count: depth + 1) + "0" + String(repeating: "]", count: depth + 1)
        guard case let .invalid(diagnostic) = JSONParser.parse(tooDeep) else {
            Issue.record("Expected a document beyond the nesting limit to be invalid")
            return
        }
        #expect(diagnostic.message.contains("nesting depth"))
        // The diagnostic points at the first container that would exceed the
        // limit.
        #expect(diagnostic.range == depth ..< (depth + 1))
    }

    @Test func nestedObjectsBeyondTheLimitAreRejectedNotCrashed() {
        var text = "null"
        for _ in 0 ..< (JSONParser.maxNestingDepth + 8) {
            text = "{\"k\":\(text)}"
        }
        guard case let .invalid(diagnostic) = JSONParser.parse(text) else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("nesting depth"))
    }
}
