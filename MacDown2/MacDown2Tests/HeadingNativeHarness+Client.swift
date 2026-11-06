import AppKit
import ApplicationServices
import Foundation
import Testing

extension HeadingNativeHarness {
    private struct ClientResult: Sendable {
        let status: Int32
        let stage: String
        let matches: Int
        let visited: Int
    }

    /// An external-style AX client lets the app main actor service the press.
    /// A synchronous in-process protocol call has no messaging timeout.
    static func pressLink(label: String) async throws {
        let result = await Task.detached { nativePress(label: label) }.value
        print("Heading AX client stage=\(result.stage) status=\(result.status) " +
            "matches=\(result.matches) visited=\(result.visited)")
        try #require(result.status == AXError.success.rawValue && result.matches == 1,
                     "The bounded native client must press exactly one real link in its focused window")
    }

    private nonisolated static func nativePress(label: String) -> ClientResult {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .init(status: status == .success ? AXError.failure.rawValue : status.rawValue,
                         stage: "focused-window", matches: 0, visited: 0)
        }
        // The Core Foundation type ID was checked before this downcast.
        let window = unsafeDowncast(value, to: AXUIElement.self)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var links: [AXUIElement] = []
        var cursor = 0
        var truncated = false
        while cursor < queue.count, cursor < 2048, ContinuousClock.now < deadline {
            let (element, depth) = queue[cursor]
            cursor += 1
            AXUIElementSetMessagingTimeout(element, 0.5)
            if attribute(kAXRoleAttribute, of: element) as? String == NSAccessibility.Role.link.rawValue,
               [kAXTitleAttribute, kAXDescriptionAttribute].contains(where: {
                   (attribute($0, of: element) as? String)?.utf8.elementsEqual(label.utf8) == true
               }), !links.contains(where: { CFEqual($0, element) }) {
                links.append(element)
            }
            if let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement], !children.isEmpty {
                let remaining = max(0, 2048 - queue.count)
                truncated = truncated || depth >= 25 || children.count > remaining
                if depth < 25 {
                    queue.append(contentsOf: children.prefix(remaining).map { ($0, depth + 1) })
                }
            }
        }
        guard !truncated, cursor == queue.count, ContinuousClock.now < deadline, links.count == 1,
              let link = links.first else {
            return .init(status: AXError.failure.rawValue, stage: "unique-link", matches: links.count, visited: cursor)
        }
        let pressed = AXUIElementPerformAction(link, kAXPressAction as CFString)
        return .init(status: pressed.rawValue, stage: "press", matches: links.count, visited: cursor)
    }

    private nonisolated static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
