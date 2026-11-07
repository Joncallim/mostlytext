import AppKit
@testable import MacDown2
import Testing

@MainActor
extension PlaceholderWindowCleanupTests {
    @Test func unmarkedWindowsAreNotStartupPlaceholders() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        defer { window.close() }
        #expect(!AppDelegate.isSwiftUIPlaceholder(window))
    }
}
