import Foundation
@testable import Preview
import SwiftUI
import Testing
import Textual

@MainActor
@Suite("Actual restored Unicode-adjacent native math geometry", .serialized)
struct PreviewMathScalarGeometryTests {
    private static let control = "MT_SCALAR_GEOMETRY_CONTROL"

    @Test func allScalarNeighborsRetainTheirOwnInlineNativeOccurrence() async throws {
        let neighbors = ["\u{600}", "\u{301}", "\u{FE0F}", "\u{200C}", "👩🏽‍💻", "漢"]
        let rows = try neighbors.enumerated().map { index, neighbor in
            let source = neighbor + "$x$" + neighbor
            let id = UUID()
            let range = (source as NSString).range(of: "$x$", options: .literal)
            let input = try PreviewMathInput(source: source, replacements: [
                .init(id: id, range: range.location ..< NSMaxRange(range), expectedSource: "$x$"),
            ])
            let label = "MT_SCALAR_NATIVE_OCCURRENCE_" + String(index)
            let attachment = AnyAttachment.math(latex: "x", style: .inline, sourceID: id)
                .withAccessibility(.init(label: label))
            return Row(
                source: source,
                label: label,
                parser: PreviewMathMarkupParser(input: input, attachments: [id: attachment])
            )
        }
        let host = try NativeMathProbeHost(Root(rows: rows), size: CGSize(width: 600, height: 500))
        defer { host.close() }
        try await host.primeAccessibility()
        let frames = try await host.waitForFrames([Self.control] + rows.map(\.label))
        try #require(frames.count == 7, "The ordinary control and all six exact native occurrences must be exposed")
        let inside = frames.allSatisfy { !$0.isEmpty && host.window.frame.contains($0) }
        let distinct = Set(frames.dropFirst().map(NSStringFromRect)).count == 6
        let data = try JSONSerialization.data(withJSONObject: [
            "positiveControlsPresent": !frames[0].isEmpty, "actualOccurrenceCount": frames.count - 1,
            "allFramesInsideHost": inside, "distinctFrames": distinct, "frames": frames.map(NSStringFromRect),
        ], options: [.sortedKeys])
        try print("MOSTLYTEXT_MATH_SCALAR_GEOMETRY " + #require(String(data: data, encoding: .utf8)))
        #expect(inside)
        #expect(distinct)
    }

    private struct Row {
        let source: String
        let label: String
        let parser: PreviewMathMarkupParser
    }

    private struct Root: View {
        let rows: [Row]
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text(PreviewMathScalarGeometryTests.control)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    InlineText(row.source, parser: row.parser)
                }
            }
            .font(.system(size: 18))
            .padding()
            .frame(width: 600, height: 500, alignment: .topLeading)
        }
    }
}
