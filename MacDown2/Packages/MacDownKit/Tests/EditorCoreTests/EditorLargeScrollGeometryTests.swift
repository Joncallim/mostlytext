import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

@MainActor
@Suite("Large editor scroll geometry")
struct EditorLargeScrollGeometryTests {
    @Test("A million-unit editor reaches its tail by scrollbar and outline reveal", .timeLimit(.minutes(2)))
    // swiftlint:disable:next function_body_length
    func largeDocumentTailRemainsReachableAndFrameResetsAfterShrink() async throws {
        let line = String(repeating: "plain words ", count: 15) + "\n"
        let source = "# Top\n\n" + String(repeating: line, count: 5800) + "\n## Tail `omega`\n"
        try #require((source as NSString).length > ContentHeightMeter.estimationThreshold)
        let model = LargeScrollSourceBox(source)
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            identity: identity, configuration: .default, store: store
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close(); store.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(store.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 800, height: 50000)
        scroll.layoutSubtreeIfNeeded()
        system.syncFrameHeightToContent()
        let tail = (source as NSString).range(of: "## Tail `omega`")
        let measured = system.measuredContentHeight
        let usage = system.layoutManager.usageBoundsForTextContainer.maxY
        #expect(measured >= usage, "The manual scroll frame must cover TextKit's estimated content")
        let repeatedStart = ContinuousClock.now
        for _ in 0 ..< 20 {
            system.syncFrameHeightToContent()
        }
        print("LARGE-FRAME-SYNC-REPEATED-20 \(ContinuousClock.now - repeatedStart)")
        let initialContainerWidth = try #require(system.textView.textContainer?.size.width)
        let bottomY = max(0, system.textView.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: bottomY))
        scroll.reflectScrolledClipView(scroll.contentView)
        let manual = try await visibleTail(system: system, scroll: scroll, tail: tail)
        let manualVisible = try #require(manual,
                                         "Dragging the scrollbar to the bottom must expose the authored tail")
        #expect(NSIntersectionRange(manualVisible, tail).length > 0,
                "Dragging the scrollbar to the bottom must expose the authored tail")

        system.scrollToVisible(utf16Range: NSRange(location: 0, length: 5))
        system.revealSelection(utf16Range: tail, flash: false)
        let revealed = try #require(system.visibleUTF16Range)
        #expect(NSIntersectionRange(revealed, tail).length > 0)
        #expect(system.selectedRange == tail)

        window.setContentSize(NSSize(width: 1600, height: 320))
        host.frame.size.width = 1600
        scroll.frame.size.width = 1600
        system.textView.frame.size.width = 1600
        scroll.layoutSubtreeIfNeeded()
        system.syncFrameHeightToContent()
        let wideContainerWidth = try #require(system.textView.textContainer?.size.width)
        #expect(wideContainerWidth > initialContainerWidth)
        #expect(system.measuredContentHeight >= system.layoutManager.usageBoundsForTextContainer.maxY)
        let wideBottomY = max(0, system.textView.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: wideBottomY))
        scroll.reflectScrolledClipView(scroll.contentView)
        let wideVisible = try await visibleTail(system: system, scroll: scroll, tail: tail)
        let settledWide = try #require(wideVisible,
                                       "After a width change, the current TextKit tail must remain reachable")
        #expect(NSIntersectionRange(settledWide, tail).length > 0)

        model.text = "short\n"
        system.setText(model.text)
        system.syncFrameHeightToContent()
        #expect(system.textView.frame.height < measured / 2,
                "A new short source must not inherit the old observed geometry floor")
        #expect(Array(system.textView.string.utf16) == Array(model.text.utf16))
    }

    private func visibleTail(system: EditorTextSystem, scroll: NSScrollView,
                             tail: NSRange) async throws -> NSRange? {
        for _ in 0 ..< 25 {
            scroll.layoutSubtreeIfNeeded()
            if let visible = system.visibleUTF16Range,
               NSIntersectionRange(visible, tail).length > 0 {
                return visible
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}

@MainActor
private final class LargeScrollSourceBox {
    var text: String
    init(_ text: String) {
        self.text = text
    }
}
