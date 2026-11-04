import FileCore
import Foundation
import Testing
@testable import TextSearch

@Suite("Replacement plan range bounds")
struct ReplacementPlanRangeBoundsTests {
    @Test
    func negativeLengthsNeverReachFoundationReplacement() async throws {
        try await checkRejected([NSRange(location: 0, length: -1)])
        try await checkRejected([NSRange(location: 2, length: Int.min)])
    }

    @Test
    func overflowingEndsAreRejectedBeforeAddition() async throws {
        try await checkRejected([NSRange(location: 1, length: Int.max)])
        try await checkRejected([NSRange(location: Int.max - 1, length: 2)])
    }

    @Test
    func invalidLocationsAndOrdinaryOutOfBoundsRangesAreRejected() async throws {
        let invalidRanges = [
            NSRange(location: -1, length: 0),
            NSRange(location: Int.min, length: 1),
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: 3, length: 1),
            NSRange(location: 4, length: 0),
        ]
        for range in invalidRanges {
            try await checkRejected([range])
        }
    }

    @Test
    func aValidPrefixDoesNotAllowALaterMalformedRangeToMutateTheFile() async throws {
        try await checkRejected([NSRange(location: 0, length: 1), NSRange(location: 2, length: Int.max)])
        try await checkRejected([NSRange(location: 0, length: 1), NSRange(location: 2, length: -1)])
    }

    @Test
    func validBoundaryUnicodeAndLineEndingBehaviorIsPreserved() throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let text = "😀x\r\n"
        try tree.write("a.md", text: text)
        let revision = try FileStore().readSnapshot(from: tree.root.appendingPathComponent("a.md")).revision
        let cases = [
            BoundaryCase(ranges: [], replacement: "X", expected: text),
            BoundaryCase(ranges: [NSRange(location: 0, length: 0)], replacement: "X", expected: "X😀x\r\n"),
            BoundaryCase(ranges: [NSRange(location: 5, length: 0)], replacement: "X", expected: "😀x\r\nX"),
            BoundaryCase(
                ranges: [NSRange(location: 0, length: 2), NSRange(location: 2, length: 1)],
                replacement: "X", expected: "XX\r\n"
            ),
            BoundaryCase(ranges: [NSRange(location: 3, length: 2)], replacement: "A\nB", expected: "😀xA\r\nB"),
            BoundaryCase(ranges: [NSRange(location: 0, length: 5)], replacement: "X", expected: "X"),
        ]
        for item in cases {
            let plan = ReplacementPlan(
                relativePath: "a.md", revision: revision,
                matches: item.ranges.map { SearchMatch(range: $0) }, replacementText: item.replacement
            )
            #expect(plan.applying(to: text) == item.expected)
        }
    }

    private struct BoundaryCase {
        let ranges: [NSRange]
        let replacement: String
        let expected: String
    }

    private func checkRejected(_ ranges: [NSRange]) async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo")
        try tree.write("b.md", text: "foo")
        let source = tree.root.appendingPathComponent("a.md")
        let original = try Data(contentsOf: source)
        let revision = try FileStore().readSnapshot(from: source).revision
        let invalid = ReplacementPlan(
            relativePath: "a.md", revision: revision,
            matches: ranges.map { SearchMatch(range: $0) }, replacementText: "X"
        )
        let valid = ReplacementPlan(
            relativePath: "b.md", revision: revision,
            matches: [SearchMatch(range: NSRange(location: 0, length: 3))], replacementText: "bar"
        )
        #expect(invalid.applying(to: "foo") == nil)
        let engine = WorkspaceReplaceEngine()
        #expect(await engine.preview(root: tree.root, plan: invalid) == .changedSinceSearch)
        let results = await engine.replace(root: tree.root, plans: [invalid, valid])
        #expect(results.map(\.outcome) == [.skippedCannotRepresent, .replaced(count: 1)])
        #expect(try Data(contentsOf: source) == original)
        #expect(try read(tree, "b.md") == "bar")
    }
}
