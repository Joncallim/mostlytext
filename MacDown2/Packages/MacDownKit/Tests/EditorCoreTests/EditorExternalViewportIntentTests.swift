import AppKit
@testable import EditorCore
import Testing

@MainActor
@Suite("External reload viewport intent")
struct EditorExternalViewportIntentTests {
    enum Navigation: CaseIterable, Sendable {
        case offset, scroll, reveal, selection, multipleSelection
    }

    private func pendingReload() throws -> (EditorTextSystem, NSScrollView) {
        let text = String(repeating: "A line that makes the editor scroll.\n", count: 160)
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scroll.documentView = system.textView
        system.scrollView = scroll
        system.textView.frame = scroll.bounds
        system.syncFrameHeightToContent()
        system.scrollOffset = 1000
        let viewport = system.viewportSnapshot()
        try #require(viewport.topVisibleUTF16Offset != nil)
        system.replaceTextFromExternal(text, preserving: viewport, clearUndo: true)
        system.frameSyncTask?.cancel()
        return (system, scroll)
    }

    @Test("new navigation supersedes either reload pass", arguments: Navigation.allCases, [false, true])
    func navigationSupersedesReload(navigation: Navigation, afterFirstPass: Bool) throws {
        let (system, _) = try pendingReload()
        if afterFirstPass {
            system.syncFrameHeightToContent()
            #expect(system.applyPendingExternalViewport())
        }
        let range = NSRange(location: 5, length: 0)
        switch navigation {
        case .offset: system.scrollOffset = 40
        case .scroll: system.scrollToVisible(utf16Range: range)
        case .reveal: system.revealSelection(utf16Range: range, flash: false)
        case .selection: system.selectedRange = range
        case .multipleSelection: system.selectionSet = EditorSelectionSet(single: range)
        }
        let newOffset = system.scrollOffset
        for _ in 0 ..< 2 {
            #expect(!system.applyPendingExternalViewport())
            system.applyPendingScrollOffset()
            #expect(system.scrollOffset == newOffset)
        }
        #expect(system.pendingExternalViewport == nil)
        #expect(system.pendingExternalViewportRevision == nil)
        #expect(system.pendingScrollOffset == nil)
    }

    @Test("only changed native selections revoke the reload")
    func changedSelectionSupersedesReload() throws {
        let (system, _) = try pendingReload()
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: system.textView)
        coordinator.textViewDidChangeSelection(notification)
        system.frameSyncTask?.cancel()
        #expect(system.pendingExternalViewport != nil)
        system.textView.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.textViewDidChangeSelection(notification)
        system.frameSyncTask?.cancel()
        #expect(!system.applyPendingExternalViewport())
        #expect(system.pendingScrollOffset == nil)
    }

    @Test("user live scroll revokes reload; layout and stale scroll views do not")
    func userScrollSupersedesReload() throws {
        let (system, scroll) = try pendingReload()
        let coordinator = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        coordinator.scrollViewDidScroll(Notification(
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        ))
        coordinator.editorLayoutDidChange(Notification(
            name: NSView.frameDidChangeNotification,
            object: system.textView
        ))
        coordinator.userDidScroll(Notification(name: NSScrollView.didLiveScrollNotification, object: NSScrollView()))
        #expect(system.pendingExternalViewport != nil)
        coordinator.userDidScroll(Notification(name: NSScrollView.didLiveScrollNotification, object: scroll))
        #expect(!system.applyPendingExternalViewport())
        #expect(system.pendingScrollOffset == nil)
    }

    @Test("cancelling a layout-free reload clears only its own raw fallback")
    func rawOffsetOwnership() {
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: "old", configuration: .default)
        system.replaceTextFromExternal(
            "new",
            preserving: .init(selectedRange: .init(location: 0, length: 0), scrollOffset: 100),
            clearUndo: true
        )
        system.frameSyncTask?.cancel()
        system.cancelPendingExternalViewport()
        #expect(system.pendingScrollOffset == nil)
        system.scrollOffset = 42
        system.cancelPendingExternalViewport()
        #expect(system.pendingScrollOffset == 42)
    }
}
