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
        let result = nativeInspect(label: label, press: false)
        lastLinkClientDiagnostic = "Native link lookup stage=\(result.stage) status=\(result.status) " +
            "matches=\(result.matches) visited=\(result.visited) candidates=\(result.candidates)"
        return result.status == AXError.success.rawValue && result.matches == 1
    }

    /// Same-process AX calls can synchronously enter AppKit providers, so the
    /// client must use the app's main thread as well as its finite API bounds.
    static func pressLink(label: String) async throws {
        let result = nativeInspect(label: label, press: true)
        print("Heading AX client stage=\(result.stage) status=\(result.status) " +
            "matches=\(result.matches) visited=\(result.visited) actions=\(result.actions)")
        try #require(result.status == AXError.success.rawValue && result.matches == 1,
                     "The bounded native client must press exactly one real link in its focused window")
    }

    private final class PressReceiver: NSObject {
        var presses = 0
        @objc func press(_: Any?) {
            presses += 1
        }
    }

    /// Discriminates AX transport from the actual TOC. The control is removed
    /// before the production fixture is inspected and never calls its actions.
    static func requireNativePressTransport(restoring window: NSWindow) throws {
        let receiver = PressReceiver()
        let button = NSButton(title: "Heading native transport control", target: receiver,
                              action: #selector(PressReceiver.press(_:)))
        button.setAccessibilityLabel("Heading native transport control")
        let control = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 50),
                               styleMask: [.titled], backing: .buffered, defer: false)
        control.isReleasedWhenClosed = false
        control.animationBehavior = .none
        control.contentView = button
        let focus = window.firstResponder
        defer {
            control.orderOut(nil)
            control.close()
            window.makeKeyAndOrderFront(nil)
            window.makeKey()
            window.makeFirstResponder(focus)
        }
        control.makeKeyAndOrderFront(nil)
        control.makeKey()
        try #require(NSApp.keyWindow === control)
        let result = nativeInspect(label: "Heading native transport control", press: true,
                                   role: NSAccessibility.Role.button.rawValue)
        print("Native AX control status=\(result.status) stage=\(result.stage) actions=\(result.actions)")
        try #require(result.status == AXError.success.rawValue && result.matches == 1 && receiver.presses == 1,
                     "The same native AX client must press a known real button exactly once")
    }

    private static func nativeInspect(label: String, press: Bool,
                                      role expectedRole: String = "AXLink") -> ClientResult {
        precondition(Thread.isMainThread)
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
            if role == expectedRole,
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
        return performPress(link: link, visited: cursor, deadline: deadline)
    }

    private static func focusedWindow() -> (AXUIElement?, Int32) {
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

    private static func performPress(link: AXUIElement, visited: Int,
                                     deadline: ContinuousClock.Instant) -> ClientResult {
        var actionNames: CFArray?
        let actionStatus = AXUIElementCopyActionNames(link, &actionNames)
        let actions = actionStatus == .success ? (actionNames as? [String] ?? []) : ["error:\(actionStatus.rawValue)"]
        guard actionStatus == .success, actions.contains(kAXPressAction) else {
            return .init(status: AXError.failure.rawValue, stage: "supported-action", matches: 1,
                         visited: visited, actions: actions)
        }
        let pressed = AXUIElementPerformAction(link, kAXPressAction as CFString)
        guard ContinuousClock.now < deadline else {
            return .init(status: AXError.failure.rawValue, stage: "press-deadline", matches: 1, visited: visited)
        }
        return .init(status: pressed.rawValue, stage: "press", matches: 1, visited: visited, actions: actions)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
