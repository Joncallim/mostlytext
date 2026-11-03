import AppKit
@testable import MacDown2
import Testing

@MainActor
struct ComponentTestHostIconTests {
    @Test func componentHostReceivesAnOwnedBitmapWithoutAFileIconLookup() throws {
        var received: NSImage?
        ComponentTestHostIcon.installIfRequired(isTestHost: true, isUITesting: false) { received = $0 }
        let image = try #require(received)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(bitmap.pixelsWide == 16 && bitmap.pixelsHigh == 16)
        #expect(bitmap.bitmapData?[0] == 0x7F)
    }

    @Test func ordinaryAndNativeUITestLaunchesKeepTheirOwnIcon() {
        var installs = 0
        for (hosted, uiTesting) in [(false, false), (false, true), (true, true)] {
            ComponentTestHostIcon.installIfRequired(isTestHost: hosted, isUITesting: uiTesting) { _ in installs += 1 }
        }
        #expect(installs == 0)
    }

    @Test func actualComponentHostHasTheOwnedBitmapInstalled() throws {
        #expect(SingleTestInstanceGuard.isRunningUnderXCTest)
        let image = try #require(NSApplication.shared.applicationIconImage)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(bitmap.pixelsWide == 16 && bitmap.pixelsHigh == 16)
        #expect(bitmap.bitmapData?[0] == 0x7F)
    }
}
