import AppKit
import ApplicationServices
import EditorCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// Actual application window, SwiftUI Preview and native link actions. This
/// helper is compiled locally and executed only in hosted macOS acceptance.
@MainActor
enum HeadingNativeHarness {
    struct Mounted {
        let fixture: TextFilterCoordinatorTests.Fixture
        let window: NSWindow
        let content: NSView
        let source: String
    }

    private struct PresentationUnavailable: Error {}

    static func source(lastHeading: String) -> String {
        let paragraphs = (0 ..< 24).map { index in
            "Paragraph \(index). " + String(repeating: "Readable ordinary text. ", count: 30)
        }.joined(separator: "\n\n")
        return "[TOC]\n\n# First\n\n" + paragraphs + "\n\n## \(lastHeading)\n"
    }

    static func mount(source: String, layout: PreviewLayoutMode) async throws -> Mounted {
        let fixture = try TextFilterCoordinatorTests.makeController(text: source)
        var transferred = false
        defer {
            if !transferred {
                MathPreviewLiveSourceTests.dispose(fixture)
            }
        }
        fixture.controller.model.tabStore.setPreviewLayout(layout, for: fixture.tabID)
        let application = NSApplication.shared
        if !NSRunningApplication.current.isFinishedLaunching {
            application.finishLaunching()
        }
        application.activate()
        let window = try #require(fixture.controller.window)
        window.setContentSize(.init(width: 900, height: 600))
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        try #require(application.keyWindow === window, "The real app window must own keyboard focus")
        try await requireOwnAccessibilityRole()
        let content = try #require(window.contentView)
        transferred = true
        return Mounted(fixture: fixture, window: window, content: content, source: source)
    }

    static func requireOwnAccessibilityRole() async throws {
        let result = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let timeout = AXUIElementSetMessagingTimeout(process, 0.5)
            guard timeout == .success else { return (timeout.rawValue, String?.none) }
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(process, kAXRoleAttribute as CFString, &role)
            return (error.rawValue, role as? String)
        }.value
        try #require(result.0 == AXError.success.rawValue && result.1 == (kAXApplicationRole as String),
                     "Initialize the actual own-process native accessibility client")
    }

    static func previewScroll(in mounted: Mounted, editor: EditorTextSystem) throws -> NSScrollView {
        var result: [NSScrollView] = []
        func visit(_ view: NSView, depth: Int) {
            guard depth < 30 else { return }
            if let scroll = view as? NSScrollView, scroll !== editor.textView.enclosingScrollView,
               scroll.window === mounted.window, let document = scroll.documentView,
               document.bounds.height > scroll.contentView.bounds.height + 50 {
                result.append(scroll)
            }
            for child in view.subviews {
                visit(child, depth: depth + 1)
            }
        }
        visit(mounted.content, depth: 0)
        try #require(result.count == 1, "The real overflowing Preview scroll view must be identifiable")
        return result[0]
    }

    static func wait(
        in mounted: Mounted, stage: String, condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            mounted.content.layoutSubtreeIfNeeded()
            mounted.window.displayIfNeeded()
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let identity = mounted.fixture.tabID.uuidString
        let parse = mounted.fixture.controller.parseStore.existingSession(for: identity)
        let attributes = nodes(in: mounted.content).prefix(150).compactMap { object -> String? in
            guard let accessible = object as? any NSAccessibilityProtocol else { return nil }
            return "\(accessible.accessibilityRole()?.rawValue ?? "nil") " +
                "\(accessible.accessibilityLabel() ?? "nil") \(accessible.accessibilityURL()?.absoluteString ?? "nil")"
        }.joined(separator: "\n")
        Issue.record("""
        Heading Preview stage: \(stage); parsed revision: \(parse?.document?.revision ?? -1);
        published bytes: \(parse?.publishedText?.utf8.count ?? 0); parsing: \(parse?.isParsing ?? false).
        \(lastLinkClientDiagnostic)
        Native accessibility attributes:\n\(attributes)
        """)
        throw PresentationUnavailable()
    }

    static func nodes(in view: NSView) -> [NSObject] {
        var result: [NSObject] = []
        var seen: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject, depth: Int) {
            guard depth <= 25, seen.count < 2048, seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            let selector = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: selector),
               let children = object.perform(selector)?.takeUnretainedValue() as? [Any] {
                for case let child as NSObject in children {
                    visit(child, depth: depth + 1)
                }
            }
            if let native = object as? NSView {
                for child in native.subviews {
                    visit(child, depth: depth + 1)
                }
            }
        }
        for case let root as NSObject in [view] + (view.accessibilityChildren() ?? []) +
            NSAccessibility.unignoredChildren(from: [view]) {
            visit(root, depth: 0)
        }
        return result
    }
}
