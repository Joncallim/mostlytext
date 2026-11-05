import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import Testing

/// Owned synthetic host for focused component probes; no app/document or external AX access.
@MainActor
struct NativeMathProbeHost<Content: View> {
    let window: NSWindow
    let view: NSHostingView<Content>
    private let previousPolicy: NSApplication.ActivationPolicy

    init(_ content: Content, size: CGSize) throws {
        let application = NSApplication.shared
        previousPolicy = application.activationPolicy()
        try #require(application.setActivationPolicy(.regular))
        if !NSRunningApplication.current.isFinishedLaunching {
            application.finishLaunching()
        }
        application.activate()
        view = NSHostingView(rootView: content)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        _ = NSApplication.shared.setActivationPolicy(previousPolicy)
    }

    func primeAccessibility() async throws {
        let role = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let timeout = AXUIElementSetMessagingTimeout(application, 0.5)
            guard timeout == .success else { return (timeout.rawValue, String?.none) }
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &value)
            return (error.rawValue, value as? String)
        }.value
        try #require(role.0 == AXError.success.rawValue && role.1 == (kAXApplicationRole as String))
    }

    func waitForFrames(
        _ labels: [String], matching predicate: ([CGRect]) -> Bool = { _ in true }
    ) async throws -> [CGRect] {
        var latest: [CGRect] = []
        for _ in 0 ..< 50 {
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let nodes = accessibilityNodes()
            latest = labels.compactMap { label in
                nodes.first(where: { strings($0).contains(label) }).flatMap(frame)
            }
            if latest.count == labels.count, latest.allSatisfy({ !$0.isEmpty }), predicate(latest) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return latest
    }

    private func frame(_ object: NSObject) -> CGRect? {
        if let value = object as? any NSAccessibilityProtocol {
            return value.accessibilityFrame()
        }
        return (object as? any NSAccessibilityElementProtocol)?.accessibilityFrame()
    }

    private func strings(_ object: NSObject) -> [String] {
        ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { name in
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue() as? String
        }
    }

    private func accessibilityNodes() -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        var result: [NSObject] = []
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
        for case let root as NSObject in [view] + (view.accessibilityChildren() ?? []) +
            NSAccessibility.unignoredChildren(from: [view]) {
            visit(root, depth: 0)
        }
        return result
    }
}
