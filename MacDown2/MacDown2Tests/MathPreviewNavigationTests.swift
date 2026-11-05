import AppKit
import EditorCore
import Foundation
@testable import MacDown2
import Testing

/// Actual app coordinator and editor, executed in hosted macOS tests only.
/// Acquire focus after all awaits, then test navigation synchronously so another
/// test cannot change source or focus between admission and selection.
@MainActor
struct MathPreviewNavigationTests {
    private struct Prepared {
        let fixture: TextFilterCoordinatorTests.Fixture
        let session: MathPreviewSession
        let frameID: UUID
        let sourceID: UUID
        let location: MathPreviewSourceLocation
    }

    private func prepare() async throws -> Prepared {
        let source = "First $x$ then second $x$."
        let fixture = try TextFilterCoordinatorTests.makeController(text: source)
        let identity = fixture.tabID.uuidString
        let parse = fixture.controller.parseStore.session(for: identity)
        await parse.parseNow(source)
        let live = try #require(fixture.coordinator.mathLiveSource(in: fixture.controller.model, identity: identity))
        let session = MathPreviewSession()
        let binding = MathPreviewSourceBinding(stamp: live.stamp, source: source)
        try await session.refresh(binding: binding, document: #require(parse.document)) {
            fixture.coordinator.mathLiveSource(in: fixture.controller.model, identity: identity)
        }
        let entry = try #require(session.evaluation?.entries.last)
        let location = MathPreviewSourceLocation(range: entry.equation.syntax.fullRange,
                                                 diagnosticOffset: entry.equation.syntax.bodyRange.lowerBound)
        let frameID = UUID()
        try #require(session.installPresentation(id: frameID, bindingID: binding.id, locations: [entry.id: location],
                                                 live: fixture.coordinator.mathLiveSource(
                                                     in: fixture.controller.model, identity: identity
                                                 )))
        return .init(fixture: fixture, session: session, frameID: frameID, sourceID: entry.id, location: location)
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
        try #require(application.keyWindow === window, "Native positive control must own the key window")
        return window
    }

    private func navigate(_ prepared: Prepared, diagnostic: Bool = false) {
        prepared.fixture.coordinator.showMathSource(
            in: prepared.fixture.controller.model, identity: prepared.fixture.tabID.uuidString,
            session: prepared.session, action: .init(frameID: prepared.frameID,
                                                     sourceID: prepared.sourceID, diagnostic: diagnostic)
        )
    }

    @Test(arguments: [false, true])
    func theOwnOccurrenceReplacesTheEntireSelectionSet(diagnostic: Bool) async throws {
        let prepared = try await prepare()
        let system = try #require(prepared.fixture.controller.editorStore.existingSystem(
            for: prepared.fixture.tabID.uuidString
        ))
        let window = try activate(prepared)
        defer { window.orderOut(nil) }
        system.selectionSet = .init(
            ranges: [.init(location: 0, length: 1), .init(location: 3, length: 1)],
            primaryIndex: 1
        )
        navigate(prepared, diagnostic: diagnostic)
        let expected = try diagnostic
            ? NSRange(location: #require(prepared.location.diagnosticOffset), length: 0)
            : NSRange(location: prepared.location.range.lowerBound, length: prepared.location.range.count)
        #expect(system.selectionSet == EditorSelectionSet(single: expected))
        #expect(system.selectedRange == expected)
        #expect(window.firstResponder === system.textView)
    }

    @Test(arguments: ["editor", "generation", "parser", "removed", "frame", "foreignID"])
    func changedLiveAuthorityCannotMoveSelection(_ change: String) async throws {
        let prepared = try await prepare()
        let fixture = prepared.fixture
        let identity = fixture.tabID.uuidString
        let system = try #require(fixture.controller.editorStore.existingSystem(for: identity))
        let window = try activate(prepared)
        defer { window.orderOut(nil) }
        let original = EditorSelectionSet(single: .init(location: 0, length: 1))
        system.selectionSet = original
        switch change {
        case "editor": system.textView.string = "Other $y$ source"
        case "generation": fixture.controller.model.tabStore.updateActiveDocument { $0.updatingText($0.text) }
        case "parser": fixture.controller.parseStore.evict(identity)
        case "removed": fixture.coordinator.controllers = []
        case "frame":
            let binding = try #require(prepared.session.binding)
            try #require(prepared.session.installPresentation(
                id: UUID(), bindingID: binding.id, locations: [prepared.sourceID: prepared.location],
                live: fixture.coordinator.mathLiveSource(in: fixture.controller.model, identity: identity)
            ))
        default:
            fixture.coordinator.showMathSource(
                in: fixture.controller.model, identity: identity, session: prepared.session,
                action: .init(frameID: prepared.frameID, sourceID: UUID(), diagnostic: false)
            )
            #expect(system.selectionSet == original)
            return
        }
        navigate(prepared)
        #expect(system.selectionSet == original)
        #expect(prepared.session.pendingNavigation == nil)
    }

    @Test func anotherKeyWindowCannotSelectTheOriginalDocumentsEquation() async throws {
        let prepared = try await prepare()
        let originalWindow = try activate(prepared)
        let other = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.orderOut(nil); originalWindow.orderOut(nil) }
        other.makeKeyAndOrderFront(nil)
        other.makeKey()
        try #require(NSApp.keyWindow === other, "Wrong-window negative control must actually own focus")
        let system = try #require(prepared.fixture.controller.editorStore.existingSystem(
            for: prepared.fixture.tabID.uuidString
        ))
        let original = EditorSelectionSet(single: .init(location: 0, length: 1))
        system.selectionSet = original
        navigate(prepared)
        #expect(system.selectionSet == original && prepared.session.pendingNavigation == nil)
    }
}
