import Foundation
@testable import JSONSupport
import Testing

/// EPIC-11 §3.4 — outline identity: key-path/array-index IDs, repeated
/// elements distinct by index, remapping across edits/formatting, labels,
/// collapse-aware rows, and duplicate-key rejection before construction.
@Suite("JSONOutlineIdentity")
struct JSONOutlineIdentityTests {
    private func items(_ text: String) -> [ContentOutlineItem] {
        switch JSONOutlineBuilder.outline(text) {
        case let .valid(items): items
        case .invalid: []
        }
    }

    @Test func objectMemberIDsUseKeyPaths() {
        let items = items(#"{"a":{"b":1},"c":[2]}"#)
        #expect(items.count == 1)
        let root = items[0]
        #expect(root.id == "$")
        #expect(root.title == "Object")
        #expect(root.children.map(\.id) == ["$.a", "$.c"])
        #expect(root.children[0].children.map(\.id) == ["$.a.b"])
    }

    @Test func arrayElementIDsUseIndices() {
        let items = items(#"[{"x":1},{"x":2}]"#)
        let root = items[0]
        #expect(root.id == "$")
        #expect(root.title == "Array")
        #expect(root.children.map(\.id) == ["$[0]", "$[1]"])
        #expect(root.children[0].children.map(\.id) == ["$[0].x"])
    }

    @Test func repeatedArrayElementsRemainDistinct() {
        let items = items(#"[1,1,1]"#)
        let root = items[0]
        #expect(root.children.map(\.id) == ["$[0]", "$[1]", "$[2]"])
        #expect(Set(root.children.map(\.id)).count == 3)
    }

    @Test func scalarRootGetsLiteralTitle() {
        let root = items("42")
        #expect(root[0].id == "$")
        #expect(root[0].title == "42")
        #expect(root[0].children.isEmpty)

        let stringRoot = items("\"hi\"")
        #expect(stringRoot[0].title == "hi")
    }

    @Test func emptyContainerLabels() {
        let objectItems = items(#"{"e":{}}"#)
        #expect(objectItems[0].children[0].title == "e { }")

        let arrayItems = items(#"{"e":[]}"#)
        #expect(arrayItems[0].children[0].title == "e [ ]")

        let rootEmpty = items("{}")
        #expect(rootEmpty[0].title == "Object")
    }

    @Test func duplicateKeysRejectBeforeOutlineConstruction() {
        let outcome = JSONOutlineBuilder.outline(#"{"a":1,"a":2}"#)
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("Duplicate object key"))
    }

    @Test func invalidJSONProducesNoItems() {
        let outcome = JSONOutlineBuilder.outline("{\"a\":")
        guard case .invalid = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
    }

    @Test func idsRemapAcrossFormatting() {
        let before = items(#"{"z":1,"a":[{"k":1}]}"#)
        guard case let .formatted(formatted) = JSONFormatter.format(#"{"z":1,"a":[{"k":1}]}"#) else {
            Issue.record("Expected formatted outcome")
            return
        }
        let after = items(formatted)
        func collect(_ items: [ContentOutlineItem]) -> [String] {
            items.flatMap { [$0.id] + collect($0.children) }
        }
        // Formatting changes whitespace, not structure: identical paths.
        #expect(collect(before) == collect(after))
    }

    @Test func visibleRowsHonorCollapse() {
        let items = items(#"{"a":{"b":1},"c":2}"#)
        let rows = JSONOutlineBuilder.visibleRows(items, collapsed: ["$.a"])
        #expect(rows.map(\.item.id) == ["$", "$.a", "$.c"])
        #expect(rows.map(\.depth) == [0, 1, 1])
    }

    @Test func collapsedRowsHideDescendants() {
        let items = items(#"{"a":{"b":{"c":1}}}"#)
        let rows = JSONOutlineBuilder.visibleRows(items, collapsed: ["$.a.b"])
        #expect(rows.map(\.item.id) == ["$", "$.a", "$.a.b"])
    }

    @Test func allIDsIsDepthFirst() {
        let items = items(#"{"a":{"b":1},"c":2}"#)
        #expect(JSONOutlineBuilder.allIDs(items) == ["$", "$.a", "$.a.b", "$.c"])
    }

    @Test func itemLookupFindsNestedNodes() {
        let items = items(#"{"a":{"b":[1,2]}}"#)
        let found = JSONOutlineBuilder.item(withID: "$.a.b[1]", in: items)
        #expect(found != nil)
        #expect(found?.title == "2")
        #expect(JSONOutlineBuilder.item(withID: "$.nope", in: items) == nil)
    }

    @Test func nodeTitlesUseDecodedStringValues() {
        let items = items(#"{"a":"\u0041\u00e9"}"#)
        #expect(items[0].children[0].title == "Aé")
    }

    @Test func nestedArrayOfObjectsLabels() {
        let items = items(#"[{"a":1}]"#)
        let root = items[0]
        // Container elements use [index]; scalar members show their value.
        #expect(root.children[0].title == "[0]")
        #expect(root.children[0].children[0].title == "1")
    }

    @Test func deepDocumentBuildsCompleteTree() {
        let items = items(#"{"a":{"b":{"c":{"d":1}}}}"#)
        #expect(items[0].children[0].children[0].children[0].children[0].id == "$.a.b.c.d")
    }
}

/// EPIC-11 §3.4 — outline source ranges: UTF-16 offsets usable directly as
/// NSRange, exact at astral/combining/LF/CRLF/CR boundaries.
@Suite("JSONOutlineSourceRanges")
struct JSONOutlineSourceRangeTests {
    private func root(_ text: String) -> ContentOutlineItem? {
        switch JSONOutlineBuilder.outline(text) {
        case let .valid(items): items.first
        case .invalid: nil
        }
    }

    @Test func memberRangesExcludeWhitespace() {
        let text = "{\n  \"a\": 1,\n  \"b\": 2\n}"
        let root = root(text)
        // Member items carry their value's range: units 9..<10 ('1') and
        // 19..<20 ('2') in `{\n  "a": 1,\n  "b": 2\n}`.
        #expect(root?.children.map(\.sourceRange) == [9 ..< 10, 19 ..< 20])
        #expect(root?.children.map(\.lineRange) == [2 ... 2, 3 ... 3])
    }

    @Test func astralScalarInsideStringAdjustsUTF16Ranges() {
        let text = "{\"a\": \"😀\"}"
        let root = root(text)
        // { " a " : ␣ " 😀 " } → value `"😀"` spans units 6..<10 (quote,
        // 2 surrogate units, quote).
        #expect(root?.children[0].sourceRange == 6 ..< 10)
    }

    @Test func combiningMarkInsideStringAdjustsUTF16Ranges() {
        let text = "{\"a\": \"e\u{301}\"}"
        let root = root(text)
        // Value `"e\u{301}"` spans units 6..<10 (quote, 'e', combining mark,
        // quote).
        #expect(root?.children[0].sourceRange == 6 ..< 10)
    }

    @Test func crlfLineNumbersCountOneBreakPerPair() {
        let text = "{\r\n  \"a\": 1,\r\n  \"b\": 2\r\n}"
        let root = root(text)
        #expect(root?.children.map(\.lineRange) == [2 ... 2, 3 ... 3])
    }

    @Test func carriageReturnOnlyLinesKeepOutlineAndSourceCoordinates() {
        let text = "{\r  \"a\": 1,\r  \"b\": 2\r}"
        let root = root(text)
        #expect(root?.lineRange == 1 ... 4)
        #expect(root?.children.map(\.lineRange) == [2 ... 2, 3 ... 3])
        let source = text as NSString
        #expect(root?.children.map { source.substring(with: NSRange(location: $0.sourceRange.lowerBound,
                                                                    length: $0.sourceRange.count)) } == ["1", "2"])
    }

    @Test func multiLineValuesSpanTheirLines() {
        let text = "{\n  \"a\": [\n    1,\n    2\n  ]\n}"
        let root = root(text)
        #expect(root?.children[0].lineRange == 2 ... 5)
        // '[' at unit 9 through ']' at unit 26.
        #expect(root?.children[0].sourceRange == 9 ..< 27)
    }

    @Test func rangesAreConsistentAfterFormatting() {
        let input = "{\"a\":{\"b\":1}}"
        guard case let .formatted(formatted) = JSONFormatter.format(input) else {
            Issue.record("Expected formatted outcome")
            return
        }
        let original = root(input)
        let reformatted = root(formatted)
        // The range *lengths* are preserved even though offsets shift.
        #expect(original?.children[0].children[0].sourceRange.count
            == reformatted?.children[0].children[0].sourceRange.count)
    }
}

/// EPIC-11 §6 — performance budgets for pure JSON work (Release targets).
///
/// The strict budgets are calibrated for Release. Debug builds are
/// unoptimized (frames, string handling, and ARC are far slower) and
/// machine-load sensitive, so Debug asserts a 5× bound instead: still tight
/// enough to catch the algorithmic regressions the budgets exist for
/// (O(n²) work on these sizes blows past it by orders of magnitude), while
/// the strict Release bounds stay in place for Release runs.
@Suite("JSONOutlinePerformance")
struct JSONOutlinePerformanceTests {
    /// 5× the Release target: the Debug guard against algorithmic regressions.
    private static let debugMultiplier = 5

    @Test func parses100KBWellUnderBudget() {
        let text = Self.makeDocument(size: 100 * 1024)
        let start = ContinuousClock.now
        guard case .valid = JSONParser.parse(text) else {
            Issue.record("Expected valid outcome")
            return
        }
        let elapsed = start.duration(to: .now)
        #if DEBUG
            #expect(elapsed < .milliseconds(50 * Self.debugMultiplier), "100KB parse took \(elapsed)")
        #else
            #expect(elapsed < .milliseconds(50), "100KB parse took \(elapsed)")
        #endif
    }

    @Test func formats100KBUnderBudget() {
        let text = Self.makeDocument(size: 100 * 1024)
        let start = ContinuousClock.now
        guard case .formatted = JSONFormatter.format(text) else {
            Issue.record("Expected formatted outcome")
            return
        }
        let elapsed = start.duration(to: .now)
        #if DEBUG
            #expect(elapsed < .milliseconds(100 * Self.debugMultiplier), "100KB format took \(elapsed)")
        #else
            #expect(elapsed < .milliseconds(100), "100KB format took \(elapsed)")
        #endif
    }

    @Test func buildsOutlineFor10000NodesUnderBudget() {
        let text = Self.makeWideDocument(nodeCount: 10000)
        let start = ContinuousClock.now
        guard case let .valid(items) = JSONOutlineBuilder.outline(text) else {
            Issue.record("Expected valid outcome")
            return
        }
        let elapsed = start.duration(to: .now)
        #expect(JSONOutlineBuilder.allIDs(items).count >= 10000)
        #if DEBUG
            #expect(elapsed < .milliseconds(200 * Self.debugMultiplier), "10k-node outline took \(elapsed)")
        #else
            #expect(elapsed < .milliseconds(200), "10k-node outline took \(elapsed)")
        #endif
    }

    /// A document of roughly `size` bytes: an object of string→number pairs.
    private static func makeDocument(size: Int) -> String {
        var parts: [String] = []
        var current = 0
        var index = 0
        while current < size {
            let entry = "\"key\(index)\": \(index)"
            current += entry.utf8.count + 2
            parts.append(entry)
            index += 1
        }
        return "{\(parts.joined(separator: ","))}"
    }

    /// An object with `nodeCount` members, each holding a nested object.
    private static func makeWideDocument(nodeCount: Int) -> String {
        var parts: [String] = []
        parts.reserveCapacity(nodeCount)
        for index in 0 ..< nodeCount {
            parts.append("\"k\(index)\": {\"v\": \(index)}")
        }
        return "{\(parts.joined(separator: ","))}"
    }
}
