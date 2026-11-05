import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import Testing
import Textual

@MainActor
@Suite("Inline occurrence accessibility and native source action", .serialized)
struct SourceAttachmentAccessibilityTests {
    private static let control = "MT_AX_DESCRIPTOR_HOST"
    private static let standalone = "MT_AX_DESCRIPTOR_STANDALONE"
    private static let first = "MT_AX_DESCRIPTOR_FIRST"
    private static let second = "MT_AX_DESCRIPTOR_SECOND"
    private static let before = "MT_AX_DESCRIPTOR_BEFORE"
    private static let after = "MT_AX_DESCRIPTOR_AFTER"
    private static let action = "MT_AX_DESCRIPTOR_SOURCE_ACTION"

    @Test func inlineOccurrencesExposeTheirOwnLabelGeometryAndNativeAction() async throws {
        _ = NSApplication.shared
        let calls = Calls()
        let firstID = UUID(), secondID = UUID()
        let first = attachment(label: Self.first, id: firstID)
        let second = attachment(label: Self.second, id: secondID)
        let standalone = attachment(label: Self.standalone, id: UUID())
        let content = VStack(alignment: .leading, spacing: 16) {
            Text(Self.control)
            standalone.body
            InlineText("synthetic descriptor probe", parser: ProbeParser(first: first, second: second))
                .textual.attachmentAccessibilityAction { calls.ids.append($0) }
        }.padding().frame(width: 260, height: 400, alignment: .topLeading)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        let role = await requestOwnRole()
        var nodes: [NSObject] = []
        for _ in 0 ..< 50 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            nodes = accessibilityNodes(host)
            if controlsPresent(nodes), node(Self.first, in: nodes) != nil, node(Self.second, in: nodes) != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try record(nodes, role: role)
        try #require(role.error == AXError.success.rawValue && role.name == (kAXApplicationRole as String))
        try #require(controlsPresent(nodes), "Actual host/standalone/both paragraph-neighbor controls must appear")
        let firstNode = try #require(node(Self.first, in: nodes))
        let secondNode = try #require(node(Self.second, in: nodes))
        #expect(firstNode !== secondNode)
        let firstFrame = try frame(firstNode)
        let secondFrame = try frame(secondNode)
        #expect(!firstFrame.isEmpty && window.frame.contains(firstFrame))
        #expect(!secondFrame.isEmpty && window.frame.contains(secondFrame))
        #expect(firstFrame != secondFrame)
        try invokeSourceAction(firstNode)
        #expect(calls.ids == [firstID])
        try invokeSourceAction(secondNode)
        #expect(calls.ids == [firstID, secondID])
        print("MOSTLYTEXT_ATTACHMENT_AX_ACTIONS " + String(calls.ids.count))
    }

    private func frame(_ object: NSObject) throws -> CGRect {
        if let element = object as? any NSAccessibilityProtocol {
            return element.accessibilityFrame()
        }
        return try #require(object as? any NSAccessibilityElementProtocol).accessibilityFrame()
    }

    private func attachment(label: String, id: UUID) -> AnyAttachment {
        AnyAttachment.math(latex: "x+y", style: .inline, sourceID: id)
            .withAccessibility(.init(label: label, actionID: id, actionName: Self.action))
    }

    private func requestOwnRole() async -> (error: Int32, name: String?) {
        await Task.detached {
            let ownProcess = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let timeout = AXUIElementSetMessagingTimeout(ownProcess, 0.5)
            guard timeout == .success else { return (timeout.rawValue, nil) }
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(ownProcess, kAXRoleAttribute as CFString, &role)
            return (error.rawValue, role as? String)
        }.value
    }

    private func accessibilityNodes(_ host: NSHostingView<some View>) -> [NSObject] {
        var result: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 24, seen.count < 512, seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            let selector = NSSelectorFromString("accessibilityChildren")
            guard object.responds(to: selector),
                  let children = object.perform(selector)?.takeUnretainedValue() as? [Any] else { return }
            for case let child as NSObject in children {
                visit(child, depth: depth + 1)
            }
        }
        for case let root as NSObject in [host] + (host.accessibilityChildren() ?? []) +
            NSAccessibility.unignoredChildren(from: [host]) {
            visit(root, depth: 0)
        }
        return result
    }

    private func strings(_ object: NSObject) -> [String] {
        ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { name in
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue() as? String
        }
    }

    private func node(_ label: String, in nodes: [NSObject]) -> NSObject? {
        nodes.first { strings($0).contains(label) }
    }

    private func controlsPresent(_ nodes: [NSObject]) -> Bool {
        let labels = nodes.flatMap(strings).joined(separator: "\n")
        return [Self.control, Self.standalone, Self.before, Self.after].allSatisfy(labels.contains)
    }

    private func invokeSourceAction(_ object: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityCustomActions")
        try #require(object.responds(to: selector))
        let actions = try #require(object.perform(selector)?.takeUnretainedValue() as? [NSAccessibilityCustomAction])
        let action = try #require(actions.first { $0.name == Self.action })
        let handler = try #require(action.handler)
        #expect(handler(), "Invoke the actual native custom action, not a separately called callback")
    }

    private func record(_ nodes: [NSObject], role: (error: Int32, name: String?)) throws {
        let value: [String: Any] = [
            "positiveControlsPresent": controlsPresent(nodes),
            "firstOwnElement": node(Self.first, in: nodes) != nil,
            "secondOwnElement": node(Self.second, in: nodes) != nil,
            "labels": nodes.flatMap(strings), "ownRoleError": role.error,
            "ownRole": role.name ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try print("MOSTLYTEXT_ATTACHMENT_AX_RESULT " + #require(String(data: data, encoding: .utf8)))
    }

    private final class Calls { var ids: [UUID] = [] }

    private struct ProbeParser: MarkupParser {
        let first: AnyAttachment
        let second: AnyAttachment
        func attributedString(for _: String) throws -> AttributedString {
            var result = AttributedString(Self.before + " " + String(repeating: "words ", count: 12))
            for attachment in [first, second] {
                var run = AttributedString("\u{FFFC}")
                run.textual.attachment = attachment
                result.append(run)
                result.append(AttributedString(" " + String(repeating: "words ", count: 8)))
            }
            result.append(AttributedString(Self.after))
            return result
        }

        private static let before = SourceAttachmentAccessibilityTests.before
        private static let after = SourceAttachmentAccessibilityTests.after
    }
}
