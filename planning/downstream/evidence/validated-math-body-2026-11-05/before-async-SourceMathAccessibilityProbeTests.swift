import AppKit
import Foundation
import SwiftUI
import Testing
import Textual

@MainActor
@Suite("Native inline math accessibility architecture probe", .serialized)
struct SourceMathAccessibilityProbeTests {
    private static let control = "MT_AX_HOST_CONTROL"
    private static let standalone = "MT_AX_STANDALONE_EQUATION"
    private static let inline = "MT_AX_INLINE_EQUATION"
    private static let before = "MT_AX_BEFORE"
    private static let after = "MT_AX_AFTER"

    @Test func recordsActualInlineEquationAccessibilityWithPositiveControls() throws {
        let base = AnyAttachment.math(latex: "x+y", style: .inline, sourceID: UUID())
        let standalone = LabeledMath(base: base, label: Self.standalone)
        let inline = LabeledMath(base: base, label: Self.inline)
        let content = VStack(alignment: .leading, spacing: 16) {
            Text(Self.control).accessibilityLabel(Text(Self.control))
            standalone.body
            InlineText("synthetic math probe", parser: ProbeParser(attachment: AnyAttachment(inline)))
        }.padding().frame(width: 480, height: 220, alignment: .topLeading)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        window.orderFront(nil)
        var labels: [String] = []
        for _ in 0 ..< 50 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            labels = accessibilityStrings(window)
            if controlsAppear(in: labels) {
                break
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let observation: [String: Any] = [
            "positiveControlsPresent": controlsAppear(in: labels),
            "inlineEquationLabelPresent": labels.contains(Self.inline),
            "labels": labels,
        ]
        let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
        print("MOSTLYTEXT_MATH_AX_PROBE " + String(decoding: data, as: UTF8.self))
        try #require(controlsAppear(in: labels), "Accessibility probe setup lacks its actual native positive controls")
        // This records a measured architecture question, not final equation/VoiceOver acceptance.
    }

    private func controlsAppear(in labels: [String]) -> Bool {
        let text = labels.joined(separator: "\n")
        return text.contains(Self.control) && text.contains(Self.standalone) &&
            text.contains(Self.before) && text.contains(Self.after)
    }

    private func accessibilityStrings(_ root: NSObject) -> [String] {
        var seen = Set<ObjectIdentifier>()
        var result: [String] = []
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 24, seen.count < 512, seen.insert(ObjectIdentifier(object)).inserted else { return }
            for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
                let selector = NSSelectorFromString(name)
                if object.responds(to: selector),
                   let value = object.perform(selector)?.takeUnretainedValue() as? String,
                   !value.isEmpty {
                    result.append(value)
                }
            }
            let selector = NSSelectorFromString("accessibilityChildren")
            guard object.responds(to: selector),
                  let children = object.perform(selector)?.takeUnretainedValue() as? [NSObject] else { return }
            for child in children {
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return result
    }

    private struct LabeledMath: Textual.Attachment {
        let base: AnyAttachment
        let label: String
        var description: String {
            base.description
        }

        var selectionStyle: AttachmentSelectionStyle {
            base.selectionStyle
        }

        var body: some View {
            base.body.accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityAddTraits(.isImage)
        }

        func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
            base.baselineOffset(in: environment)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
            base.sizeThatFits(proposal, in: environment)
        }
    }

    private struct ProbeParser: MarkupParser {
        let attachment: AnyAttachment
        func attributedString(for _: String) throws -> AttributedString {
            var result = AttributedString(Self.before + " ")
            var equation = AttributedString("\u{FFFC}")
            equation.textual.attachment = attachment
            result.append(equation)
            result.append(AttributedString(" " + Self.after))
            return result
        }

        private static let before = SourceMathAccessibilityProbeTests.before
        private static let after = SourceMathAccessibilityProbeTests.after
    }
}
