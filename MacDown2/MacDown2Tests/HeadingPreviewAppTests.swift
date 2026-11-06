import AppKit
import EditorCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// No direct session refresh or coordinator action supplies acceptance here.
/// Press the link exposed by the complete, actually mounted production Preview.
@MainActor
struct HeadingPreviewAppTests {
    struct HeadingCase: Sendable {
        let title: String
        let fragment: String
    }

    @Test func malformedMarkupIsolatesTheTOCAndRealLinksRecoverAfterCorrection() async throws {
        let valid = "[TOC]\n\n# Target\n"
        let mounted = try await HeadingNativeHarness.mount(source: valid, layout: .split(fraction: 0.5))
        defer { MathPreviewLiveSourceTests.dispose(mounted.fixture) }
        try await HeadingNativeHarness.wait(in: mounted, stage: "initial real TOC link") {
            HeadingNativeHarness.link(fragment: "target", in: mounted.content) != nil
        }
        let broken = "<div title='unterminated>\n\n" + valid
        mounted.fixture.controller.model.tabStore.updateActiveDocument { $0.updatingText(broken) }
        try await HeadingNativeHarness.wait(in: mounted, stage: "unverifiable TOC isolated with a diagnostic") {
            HeadingNativeHarness
                .link(fragment: "target", in: mounted.content) == nil && hasDiagnostics(in: mounted.content)
        }
        #expect(mounted.fixture.controller.model.activeDocument?.text.utf8.elementsEqual(broken.utf8) == true)
        mounted.fixture.controller.model.tabStore.updateActiveDocument { $0.updatingText(valid) }
        try await HeadingNativeHarness.wait(in: mounted, stage: "corrected TOC recovery") {
            HeadingNativeHarness
                .link(fragment: "target", in: mounted.content) != nil && !hasDiagnostics(in: mounted.content)
        }
        let link = try #require(HeadingNativeHarness.link(fragment: "target", in: mounted.content))
        let system = try #require(mounted.fixture.controller.editorStore
            .existingSystem(for: mounted.fixture.tabID.uuidString))
        mounted.window.makeKeyAndOrderFront(nil)
        mounted.window.makeKey()
        try #require(NSApp.keyWindow === mounted.window)
        system.selectionSet = .init(single: .init(location: 0, length: 0))
        #expect(link.accessibilityPerformPress())
        let expected = (valid as NSString).range(of: "# Target", options: .literal)
        try await HeadingNativeHarness.wait(in: mounted, stage: "recovered native link action") {
            system.selectionSet == EditorSelectionSet(single: expected)
        }
    }

    nonisolated static let headingCases: [HeadingCase] = [
        .init(title: "Last heading", fragment: "last-heading"),
        .init(title: "東京", fragment: "東京"),
    ]

    @Test(arguments: headingCases)
    func realTOCPressSelectsItsOriginalHeadingAndScrollsTheNativePreview(_ heading: HeadingCase) async throws {
        let source = HeadingNativeHarness.source(lastHeading: heading.title)
        let mounted = try await HeadingNativeHarness.mount(source: source, layout: .split(fraction: 0.5))
        defer { MathPreviewLiveSourceTests.dispose(mounted.fixture) }
        try await HeadingNativeHarness.wait(in: mounted, stage: "linked TOC publication") {
            HeadingNativeHarness.link(fragment: heading.fragment, in: mounted.content) != nil
        }
        let link = try #require(HeadingNativeHarness.link(fragment: heading.fragment, in: mounted.content))
        #expect(link.accessibilityLabel()?.contains(heading.title) == true)
        let system = try #require(mounted.fixture.controller.editorStore
            .existingSystem(for: mounted.fixture.tabID.uuidString))
        try #require(system.textView.window === mounted.window && !system.isDetachedFromEditorView)
        let preview = try HeadingNativeHarness.previewScroll(in: mounted, editor: system)
        let before = preview.contentView.bounds.origin.y
        mounted.window.makeKeyAndOrderFront(nil)
        mounted.window.makeKey()
        try #require(NSApp.keyWindow === mounted.window)
        link.setAccessibilityFocused(true)
        let focus = mounted.window.firstResponder
        system.selectionSet = .init(
            ranges: [.init(location: 0, length: 1), .init(location: 2, length: 1)],
            primaryIndex: 1
        )
        try #require(system.selectionSet.ranges.count == 2)
        #expect(link.accessibilityPerformPress(), "Invoke the actual native TOC link press handler")
        let expected = (source as NSString).range(of: "## " + heading.title, options: .literal)
        try #require(expected.location != NSNotFound)
        try await HeadingNativeHarness.wait(in: mounted, stage: "own heading selection and Preview scroll") {
            system.selectionSet == EditorSelectionSet(single: expected) && preview.contentView.bounds.origin
                .y > before + 50
        }
        #expect(system.selectedRange == expected)
        #expect(mounted.window.firstResponder === focus)
        #expect(mounted.fixture.controller.model.activeDocument?.text.utf8.elementsEqual(source.utf8) == true)
    }

    @Test func previewOnlyTOCPressScrollsWithoutMountingSelectingOrFocusingTheEditor() async throws {
        let source = HeadingNativeHarness.source(lastHeading: "Last heading")
        let mounted = try await HeadingNativeHarness.mount(source: source, layout: .previewOnly)
        defer { MathPreviewLiveSourceTests.dispose(mounted.fixture) }
        let system = try #require(mounted.fixture.controller.editorStore
            .existingSystem(for: mounted.fixture.tabID.uuidString))
        try await HeadingNativeHarness.wait(in: mounted, stage: "Preview-only linked TOC and editor detachment") {
            system.isDetachedFromEditorView && HeadingNativeHarness
                .link(fragment: "last-heading", in: mounted.content) != nil
        }
        let link = try #require(HeadingNativeHarness.link(fragment: "last-heading", in: mounted.content))
        let preview = try HeadingNativeHarness.previewScroll(in: mounted, editor: system)
        let before = preview.contentView.bounds.origin.y
        mounted.window.makeKeyAndOrderFront(nil)
        mounted.window.makeKey()
        try #require(NSApp.keyWindow === mounted.window)
        link.setAccessibilityFocused(true)
        let focus = mounted.window.firstResponder
        try #require(focus !== system.textView, "Preview-only focus must be outside the detached editor")
        let original = EditorSelectionSet(
            ranges: [.init(location: 0, length: 1), .init(location: 2, length: 1)],
            primaryIndex: 1
        )
        system.selectionSet = original
        #expect(link.accessibilityPerformPress())
        try await HeadingNativeHarness.wait(in: mounted, stage: "Preview-only scroll without editor mount") {
            preview.contentView.bounds.origin.y > before + 50
        }
        #expect(system.isDetachedFromEditorView && system.selectionSet == original)
        #expect(mounted.fixture.controller.model.tabStore.activeTab?.previewLayout == .previewOnly)
        #expect(mounted.window.firstResponder === focus && mounted.window.firstResponder !== system.textView)
    }

    private func hasDiagnostics(in content: NSView) -> Bool {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return HeadingNativeHarness.nodes(in: content).contains { object in
            object.responds(to: selector) &&
                object.perform(selector)?.takeUnretainedValue() as? String == "previewDiagnosticsBadge"
        }
    }
}
