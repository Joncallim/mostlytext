import AppKit
@testable import MacDown2
import Testing

/// Review pass 1: the launch-time placeholder cleanup closed the first-run
/// welcome window ~100 ms after it appeared, completing onboarding unseen.
@MainActor
struct PlaceholderWindowCleanupTests {
    @Test func theFirstRunWelcomeWindowIsNotAPlaceholder() throws {
        let controller = FirstRunWindowController(onStartWriting: {}, onOpenSample: {}, onClose: {})
        let window = try #require(controller.window)
        AppDelegate.markSwiftUIPlaceholder(window)
        #expect(!AppDelegate.isSwiftUIPlaceholder(window))
    }

    @Test func anExplicitlyMarkedStartupWindowIsAPlaceholder() {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        defer { window.close() }
        AppDelegate.markSwiftUIPlaceholder(window)
        #expect(AppDelegate.isSwiftUIPlaceholder(window))
        let controller = FirstRunWindowController(onStartWriting: {}, onOpenSample: {}, onClose: {})
        window.delegate = controller
        #expect(!AppDelegate.isSwiftUIPlaceholder(window))
    }

    @Test func attachingTheStartupMarkerMarksItsOwnWindow() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        defer { window.close() }
        #expect(!AppDelegate.isSwiftUIPlaceholder(window))
        window.contentView = StartupPlaceholderMarkerView(frame: .zero)
        #expect(AppDelegate.isSwiftUIPlaceholder(window))
    }
}
