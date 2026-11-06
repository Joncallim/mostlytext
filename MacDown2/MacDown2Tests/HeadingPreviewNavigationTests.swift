import AppKit
import EditorCore
import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing

/// Coordinator boundaries use the actual registered model/parser/TextKit editor.
/// Separate app-shell controls press the real native link in SwiftUI Preview.
@MainActor
struct HeadingPreviewNavigationTests {
    private struct Prepared {
        let fixture: TextFilterCoordinatorTests.Fixture
        let session: HeadingPreviewSession
        let action: HeadingPreviewAction
        let scroll: ScrollSyncController
    }

    private func prepare() async throws -> Prepared {
        let source = "[TOC]\n\n# A\n\n# A\n\n## Last\n"
        let fixture = try MathPreviewLiveSourceTests.makeMountedController(text: source)
        var transferred = false
        defer {
            if !transferred {
                MathPreviewLiveSourceTests.dispose(fixture)
            }
        }
        let identity = fixture.tabID.uuidString
        let parse = fixture.controller.parseStore.session(for: identity)
        await parse.parseNow(source)
        let document = try #require(parse.document)
        let live = try #require(fixture.coordinator.previewLiveSource(in: fixture.controller.model, identity: identity))
        let binding = PreviewSourceBinding(stamp: live.stamp, source: source)
        let session = HeadingPreviewSession()
        await session.refresh(binding: binding, document: document) {
            fixture.coordinator.previewLiveSource(in: fixture.controller.model, identity: identity)
        }
        let preparation = try #require(session.preparation)
        let heading = try #require(preparation.index.headings.last)
        let blocks = PreviewBlock.blocks(from: document, text: source)
        let scroll = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: Dictionary(uniqueKeysWithValues: blocks.indices.map { ($0, 100.0) })
        )
        let system = try #require(fixture.controller.editorStore.existingSystem(for: identity))
        let window = try #require(fixture.controller.window)
        try #require(system.textView.window === window)
        // This fixture owns the manually attached native scroll view throughout preparation.
        // Keep its direct-owner state explicit before synchronous navigation assertions.
        print("Heading direct fixture after awaits: detached=\(system.isDetachedFromEditorView)")
        system.setAwaitingEditorView(false)
        transferred = true
        return .init(fixture: fixture, session: session,
                     action: .init(bindingID: binding.id, heading: heading, identity: preparation.index.identity),
                     scroll: scroll)
    }

    private func activate(_ prepared: Prepared) throws -> NSWindow {
        let application = NSApplication.shared
        if !NSRunningApplication.current.isFinishedLaunching {
            application.finishLaunching()
        }
        application.activate()
        let window = try #require(prepared.fixture.controller.window)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        try #require(application.keyWindow === window)
        return window
    }

    private func navigate(_ prepared: Prepared, action: HeadingPreviewAction? = nil) {
        prepared.fixture.coordinator.showHeading(
            in: prepared.fixture.controller.model, identity: prepared.fixture.tabID.uuidString,
            session: prepared.session, action: action ?? prepared.action, scroll: prepared.scroll
        )
    }

    @Test func anOwnHeadingReplacesAllCaretsAndKeepsTheCurrentFirstResponder() async throws {
        let prepared = try await prepare()
        defer { MathPreviewLiveSourceTests.dispose(prepared.fixture) }
        let system = try #require(prepared.fixture.controller.editorStore
            .existingSystem(for: prepared.fixture.tabID.uuidString))
        let window = try activate(prepared)
        try #require(window.makeFirstResponder(system.textView))
        let focus = window.firstResponder
        system.selectionSet = .init(
            ranges: [.init(location: 0, length: 1), .init(location: 2, length: 1)],
            primaryIndex: 1
        )
        try #require(!system.isDetachedFromEditorView && system.textView.window === window)
        navigate(prepared)
        let range = prepared.action.heading.sourceUTF16Range
        let expected = NSRange(location: range.lowerBound, length: range.count)
        #expect(system.selectionSet == EditorSelectionSet(single: expected) && system.selectedRange == expected)
        #expect(window.firstResponder === focus && prepared.scroll.headingJumpID != nil)
        #expect(prepared.scroll.consumeHeadingJump()?.block.blockIndex == 3)
    }

    @Test(arguments: ["editor", "generation", "parser", "removed", "binding"])
    func changedLiveAuthorityCannotSelectOrQueueAScroll(_ change: String) async throws {
        let prepared = try await prepare()
        defer { MathPreviewLiveSourceTests.dispose(prepared.fixture) }
        let fixture = prepared.fixture
        let identity = fixture.tabID.uuidString
        let system = try #require(fixture.controller.editorStore.existingSystem(for: identity))
        _ = try activate(prepared)
        var action = prepared.action
        switch change {
        case "editor": system.textView.string = "# Other\n"
        case "generation": fixture.controller.model.tabStore.updateActiveDocument { $0.edited(text: $0.text) }
        case "parser": fixture.controller.parseStore.evict(identity)
        case "removed": fixture.coordinator.controllers = []
        default: action = .init(bindingID: UUID(), heading: action.heading, identity: action.identity)
        }
        let original = EditorSelectionSet(single: .init(location: 0, length: 1))
        system.selectionSet = original
        navigate(prepared, action: action)
        #expect(system.selectionSet == original && prepared.scroll.headingJumpID == nil)
        if change == "parser" {
            #expect(fixture.controller.parseStore.existingSession(for: identity) == nil)
        }
    }

    @Test func anotherKeyWindowCannotBorrowThisDocumentsHeading() async throws {
        let prepared = try await prepare()
        defer { MathPreviewLiveSourceTests.dispose(prepared.fixture) }
        _ = try activate(prepared)
        let other = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.orderOut(nil); other.close() }
        other.makeKeyAndOrderFront(nil)
        other.makeKey()
        try #require(NSApp.keyWindow === other)
        let system = try #require(prepared.fixture.controller.editorStore
            .existingSystem(for: prepared.fixture.tabID.uuidString))
        let original = EditorSelectionSet(single: .init(location: 0, length: 1))
        system.selectionSet = original
        navigate(prepared)
        #expect(system.selectionSet == original && prepared.scroll.headingJumpID == nil)
    }

    @Test func aQueuedScrollRechecksSourceAfterTheInitialValidPress() async throws {
        let prepared = try await prepare()
        defer { MathPreviewLiveSourceTests.dispose(prepared.fixture) }
        _ = try activate(prepared)
        navigate(prepared)
        try #require(prepared.scroll.headingJumpID != nil)
        let system = try #require(prepared.fixture.controller.editorStore
            .existingSystem(for: prepared.fixture.tabID.uuidString))
        system.textView.string = "# Other\n"
        #expect(prepared.scroll.consumeHeadingJump() == nil)
        #expect(prepared.scroll.headingJumpID == nil)
    }

    @Test func anAttachedSheetCannotAuthorizeHeadingNavigation() async throws {
        let prepared = try await prepare()
        defer { MathPreviewLiveSourceTests.dispose(prepared.fixture) }
        let window = try activate(prepared)
        let sheet = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet, completionHandler: nil)
        defer { window.endSheet(sheet); sheet.orderOut(nil); sheet.close() }
        try #require(window.attachedSheet === sheet)
        let system = try #require(prepared.fixture.controller.editorStore
            .existingSystem(for: prepared.fixture.tabID.uuidString))
        let original = EditorSelectionSet(single: .init(location: 0, length: 1))
        system.selectionSet = original
        navigate(prepared)
        #expect(system.selectionSet == original && prepared.scroll.headingJumpID == nil)
    }
}
