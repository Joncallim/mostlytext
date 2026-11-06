import AppKit
@testable import MacDown2
import Testing

@MainActor
@Suite("Disabled validated export sheet cancellation")
struct ValidatedExportPanelTests {
    @Test func taskCancellationDismissesTheRealSheet() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        // Swift owns this standalone window; close must not release it a second time.
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        var presented = false
        var panel: NSSavePanel?
        let task = Task { @MainActor in
            await ValidatedExportPanel.chooseTarget(
                in: window, defaultName: "cancelled", directory: nil
            ) { shown in
                panel = shown
                presented = shown.sheetParent === window
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !presented, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(presented)
        task.cancel()
        let result = await task.value
        #expect(result == nil)
        let detachmentDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while panel?.sheetParent != nil, ContinuousClock.now < detachmentDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(panel?.sheetParent == nil)
    }
}
