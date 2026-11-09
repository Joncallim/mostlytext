import AppKit
import ApplicationServices
import EditorCore
import Foundation
@testable import MacDown2
import Math
import Testing

/// The actual SwiftUI app shell performs parsing, analysis and presentation.
/// No direct session refresh or replacement native parser is used by this test.
@MainActor
struct MathPreviewRecoveryTests {
    private struct PresentationNotPublished: Error {}

    @Test func mountedPreviewRecoversFromMalformedSourceAndRemovesStaleAttachments() async throws {
        let malformed = "# Math recovery control\n\n$\\unknowncommand$"
        let valid = "# Math recovery control\n\n$x$"
        let fixture = try TextFilterCoordinatorTests.makeController(text: malformed)
        defer { MathPreviewLiveSourceTests.dispose(fixture) }
        fixture.controller.model.tabStore.setPreviewLayout(.split(fraction: 0.5), for: fixture.tabID)
        let window = try #require(fixture.controller.window)
        window.setContentSize(.init(width: 900, height: 600))
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        // SwiftUI lazily constructs its virtual accessibility children. Use
        // the same bounded own-process request as the qualified native probe;
        // do not treat an uninitialized accessibility tree as Preview state.
        try await requireOwnAccessibilityRole()
        let content = try #require(window.contentView)
        let equation = MathDiagnosticText.equationLabel("x", isDisplay: false)
        try await waitForPresentation(in: fixture, stage: "initial malformed source") {
            has("mathPreviewNotices", attribute: "accessibilityIdentifier", in: content)
        }
        #expect(!has(equation, attribute: "accessibilityLabel", in: content))

        // Exercise the real model -> editor -> parse -> math -> native view
        // publication path, including its exact-source observer and task keys.
        fixture.controller.model.tabStore.updateActiveDocument { $0.updatingText(valid) }
        try await waitForPresentation(in: fixture, stage: "valid equation recovery") {
            !has("mathPreviewNotices", attribute: "accessibilityIdentifier", in: content) &&
                has(equation, attribute: "accessibilityLabel", in: content)
        }
        #expect(fixture.controller.model.activeDocument?.text == valid)
        #expect(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString)?.textView.string == valid)
        let (system, own) = try selectRenderedEquation(in: fixture, window: window, label: equation)

        fixture.controller.model.tabStore.setPreviewLayout(.previewOnly, for: fixture.tabID)
        try await waitForPresentation(in: fixture, stage: "preview-only detachment") {
            system.isDetachedFromEditorView && has(equation, attribute: "accessibilityLabel", in: content)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        try #require(NSApp.keyWindow === window)
        system.selectionSet = .init(single: .init(location: 0, length: 0))
        try invokeSourceAction(for: equation, in: content)
        // The production mount/layout callback must finish this action; the
        // test never calls the coordinator's completion method directly.
        try await waitForPresentation(in: fixture, stage: "source action remount") {
            !system.isDetachedFromEditorView && system.textView.window === window &&
                system.selectionSet == EditorSelectionSet(single: own) && window.firstResponder === system.textView
        }

        fixture.controller.model.tabStore.updateActiveDocument { $0.updatingText(malformed) }
        try await waitForPresentation(in: fixture, stage: "malformed source after recovery") {
            has("mathPreviewNotices", attribute: "accessibilityIdentifier", in: content) &&
                !has(equation, attribute: "accessibilityLabel", in: content)
        }
        #expect(fixture.controller.model.activeDocument?.text == malformed)
    }

    private func requireOwnAccessibilityRole() async throws {
        let result = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let timeout = AXUIElementSetMessagingTimeout(process, 0.5)
            guard timeout == .success else { return (timeout.rawValue, String?.none) }
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(process, kAXRoleAttribute as CFString, &role)
            return (error.rawValue, role as? String)
        }.value
        try #require(result.0 == AXError.success.rawValue && result.1 == (kAXApplicationRole as String),
                     "The actual native accessibility client must be initialized")
    }

    private func selectRenderedEquation(
        in fixture: TextFilterCoordinatorTests.Fixture, window: NSWindow, label: String
    ) throws -> (EditorTextSystem, NSRange) {
        let source = try #require(fixture.controller.model.activeDocument?.text)
        let system = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        try #require(system.textView.window === window, "The real editor must be mounted in its own app window")
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        try #require(NSApp.keyWindow === window)
        system.selectionSet = .init(
            ranges: [.init(location: 0, length: 1), .init(location: 3, length: 1)],
            primaryIndex: 1
        )
        try invokeSourceAction(for: label, in: #require(window.contentView))
        let own = (source as NSString).range(of: "$x$", options: .literal)
        try #require(own.location != NSNotFound)
        #expect(system.selectionSet == EditorSelectionSet(single: own))
        #expect(system.selectedRange == own)
        return (system, own)
    }

    private func waitForPresentation(
        in fixture: TextFilterCoordinatorTests.Fixture, stage: String, condition: () -> Bool
    ) async throws {
        let window = try #require(fixture.controller.window)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let identity = fixture.tabID.uuidString
        let parse = fixture.controller.parseStore.existingSession(for: identity)
        let editor = fixture.controller.editorStore.existingSystem(for: identity)
        let attributes = window.contentView.map { view in
            nodes(in: view).prefix(100).map { object in
                ["accessibilityIdentifier", "accessibilityLabel", "accessibilityValue"].compactMap { name -> String? in
                    let selector = NSSelectorFromString(name)
                    guard object.responds(to: selector),
                          let value = object.perform(selector)?.takeUnretainedValue() as? String else { return nil }
                    return "\(name)=\(value.prefix(100))"
                }.joined(separator: ", ")
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        } ?? "No content view"
        Issue.record("""
        Preview stage: \(stage). Model: \(fixture.controller.model.activeDocument?.text ?? "nil").
        Published: \(parse?.publishedText ?? "nil"); parsing: \(parse?.isParsing ?? false).
        Editor: \(editor?.textView.string ?? "nil"); mounted: \(editor?.textView.window === window).
        Registered: \(fixture.coordinator.controllers.contains { $0 === fixture.controller }).
        Native accessibility attributes:\n\(attributes)
        """)
        throw PresentationNotPublished()
    }

    private func invokeSourceAction(for label: String, in view: NSView) throws {
        let labelSelector = NSSelectorFromString("accessibilityLabel")
        let actionSelector = NSSelectorFromString("accessibilityCustomActions")
        let object = try #require(nodes(in: view).first { object in
            object.responds(to: labelSelector) &&
                object.perform(labelSelector)?.takeUnretainedValue() as? String == label &&
                object.responds(to: actionSelector)
        })
        let actions = try #require(object.perform(actionSelector)?
            .takeUnretainedValue() as? [NSAccessibilityCustomAction])
        let action = try #require(actions.first { $0.name == MathDiagnosticText.sourceAction })
        let handler = try #require(action.handler)
        #expect(handler(), "Invoke the actual native occurrence action in the production Preview")
    }

    private func has(_ value: String, attribute: String, in view: NSView) -> Bool {
        let selector = NSSelectorFromString(attribute)
        return nodes(in: view).contains { object in
            object.responds(to: selector) && object.perform(selector)?.takeUnretainedValue() as? String == value
        }
    }

    private func nodes(in view: NSView) -> [NSObject] {
        var result: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
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
