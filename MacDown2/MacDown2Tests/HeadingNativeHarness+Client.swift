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
        var actions: [String] = []
        var candidates: [String] = []
    }

    static var lastLinkClientDiagnostic = ""

    static func hasLink(label: String) async -> Bool {
        let result = await Task.detached { nativeInspect(label: label, press: false) }.value
        lastLinkClientDiagnostic = "Native link lookup stage=\(result.stage) status=\(result.status) " +
            "matches=\(result.matches) visited=\(result.visited) candidates=\(result.candidates)"
        return result.status == AXError.success.rawValue && result.matches == 1
    }

    /// An external-style AX client lets the app main actor service the press.
    /// A synchronous in-process protocol call has no messaging timeout.
    static func pressLink(label: String) async throws {
        let result = await Task.detached { nativeInspect(label: label, press: true) }.value
        print("Heading AX client stage=\(result.stage) status=\(result.status) " +
            "matches=\(result.matches) visited=\(result.visited) actions=\(result.actions)")
        try #require(result.status == AXError.success.rawValue && result.matches == 1,
                     "The bounded native client must press exactly one real link in its focused window")
    }

    private nonisolated static func nativeInspect(label: String, press: Bool) -> ClientResult {
        let (window, status) = focusedWindow()
        guard let window else {
            return .init(status: status, stage: "focused-window", matches: 0, visited: 0)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var links: [AXUIElement] = []
        var candidates: [String] = []
        var cursor = 0
        var truncated = false
        while cursor < queue.count, cursor < 2048, ContinuousClock.now < deadline {
            let (element, depth) = queue[cursor]
            cursor += 1
            AXUIElementSetMessagingTimeout(element, 0.5)
            let role = attribute(kAXRoleAttribute, of: element) as? String
            let title = attribute(kAXTitleAttribute, of: element) as? String
            let description = attribute(kAXDescriptionAttribute, of: element) as? String
            if candidates.count < 32, role == NSAccessibility.Role.link.rawValue || title != nil || description != nil {
                candidates.append("\(role ?? "nil") title=\(String((title ?? "").prefix(160))) " +
                    "description=\(String((description ?? "").prefix(160)))")
            }
            if role == NSAccessibility.Role.link.rawValue,
               [title, description].contains(where: { $0?.utf8.elementsEqual(label.utf8) == true }),
               !links.contains(where: { CFEqual($0, element) }) {
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
            return .init(
                status: AXError.failure.rawValue,
                stage: "unique-link",
                matches: links.count,
                visited: cursor,
                candidates: candidates
            )
        }
        guard press else {
            return .init(status: AXError.success.rawValue, stage: "unique-link", matches: 1, visited: cursor)
        }
        return performPress(link: link, visited: cursor)
    }

    private nonisolated static func focusedWindow() -> (AXUIElement?, Int32) {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return (nil, status == .success ? AXError.failure.rawValue : status.rawValue)
        }
        // The Core Foundation type ID was checked before this downcast.
        return (unsafeDowncast(value, to: AXUIElement.self), status.rawValue)
    }

    private nonisolated static func performPress(link: AXUIElement, visited: Int) -> ClientResult {
        var actionNames: CFArray?
        let actionStatus = AXUIElementCopyActionNames(link, &actionNames)
        let actions = actionStatus == .success ? (actionNames as? [String] ?? []) : ["error:\(actionStatus.rawValue)"]
        let pressed = AXUIElementPerformAction(link, kAXPressAction as CFString)
        return .init(status: pressed.rawValue, stage: "press", matches: 1, visited: visited, actions: actions)
    }

    private nonisolated static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
