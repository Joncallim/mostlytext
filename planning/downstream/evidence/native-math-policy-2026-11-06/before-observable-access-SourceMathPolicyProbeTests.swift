import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
@testable import Textual

@MainActor
@Suite("Native math placement and font environment", .serialized)
struct SourceMathPolicyProbeTests {
    private static let control = "MT_MATH_FONT_CONTROL"
    private static let equation = "MT_MATH_FONT_EQUATION"

    @Test func accessibleWrappersPreserveActualDisplayParagraphClassification() throws {
        let display = AnyAttachment.math(latex: "x+y", style: .display, sourceID: UUID())
        let wrapped = display.withAccessibility(.init(label: "display", actionID: UUID(), actionName: "source"))
        try record("MOSTLYTEXT_MATH_PLACEMENT_PROBE ", [
            "displayBaseClassified": paragraph(display).isMathBlock,
            "displayWrappedClassified": paragraph(wrapped).isMathBlock,
        ])
        #expect(paragraph(display).isMathBlock, "Original public display factory is the positive control")
        #expect(paragraph(wrapped).isMathBlock, "Opt-in semantics must not change display placement")
        #expect(paragraph(wrapped.withAccessibility(.init(label: "replacement descriptor"))).isMathBlock)
        let inline = AnyAttachment.math(latex: "x+y", style: .inline, sourceID: UUID())
        #expect(!paragraph(inline).isMathBlock)
        #expect(!paragraph(inline.withAccessibility(.init(label: "inline"))).isMathBlock)
        var mixed = AttributedString("before ")
        mixed.append(paragraph(wrapped))
        #expect(!mixed.isMathBlock, "Surrounding authored text must not become a display-only paragraph")
    }

    @Test func unchangedInlineContentUpdatesItsGeometryWhenOnlyTheFontChanges() async throws {
        let state = FontState()
        let attachment = AnyAttachment.math(latex: "x+y", style: .inline, sourceID: UUID())
            .withAccessibility(.init(label: Self.equation))
        let root = FontRoot(state: state, attachment: attachment)
        let host = try NativeMathProbeHost(root, size: CGSize(width: 420, height: 220))
        defer { host.close() }
        try await host.primeAccessibility()
        let before = try await host.waitForFrames([Self.control, Self.equation])
        try #require(before.count == 2 && before.allSatisfy { !$0.isEmpty && host.window.frame.contains($0) },
                     "Both actual native font controls must exist before comparing updates")
        state.size = 28
        let after = try await host.waitForFrames([Self.control, Self.equation]) { frames in
            frames[0].height > before[0].height * 1.5 && frames[1].height > before[1].height * 1.5
        }
        let controlUpdated = after.count == 2 && after[0].height > before[0].height * 1.5
        let geometryUpdated = after.count == 2 && after[1].height > before[1].height * 1.5
        try record("MOSTLYTEXT_MATH_FONT_PROBE ", [
            "positiveControlsPresent": before.count == 2 && after.count == 2,
            "fontControlUpdated": controlUpdated, "attachmentGeometryUpdated": geometryUpdated,
            "before": before.map(NSStringFromRect), "after": after.map(NSStringFromRect),
        ])
        try #require(controlUpdated, "An unchanged ordinary-text control is a host/update failure")
        #expect(geometryUpdated, "Fixed content/container must not retain metrics from the old font")
    }

    private func paragraph(_ attachment: AnyAttachment) -> AttributedString {
        var value = AttributedString("\u{FFFC}")
        value.textual.attachment = attachment
        return value
    }

    private func record(_ prefix: String, _ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try print(prefix + #require(String(data: data, encoding: .utf8)))
    }

    @Observable
    private final class FontState { var size: CGFloat = 14 }

    private struct FontRoot: View {
        let state: FontState
        let attachment: AnyAttachment
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(SourceMathPolicyProbeTests.control)
                InlineText("fixed font probe", parser: ProbeParser(attachment: attachment))
            }
            .font(.system(size: state.size))
            .padding()
            .frame(width: 420, height: 220, alignment: .topLeading)
        }
    }

    private struct ProbeParser: MarkupParser {
        let attachment: AnyAttachment
        func attributedString(for _: String) throws -> AttributedString {
            var value = AttributedString("\u{FFFC}")
            value.textual.attachment = attachment
            return value
        }
    }
}
