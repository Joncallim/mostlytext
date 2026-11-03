import AppKit
import Foundation
@testable import MacDown2
import Testing

@MainActor
struct ComponentTestHostIconTests {
    @Test func componentHostReceivesAnOwnedBitmapWithoutAFileIconLookup() throws {
        var received: NSImage?
        ComponentTestHostPresentation.installIconIfRequired(isTestHost: true, isUITesting: false) { received = $0 }
        let image = try #require(received)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(bitmap.pixelsWide == 16 && bitmap.pixelsHigh == 16)
        #expect(bitmap.bitmapData?[0] == 0)
        #expect(bitmap.bitmapData?[3] == 0xFF)
        #expect(bitmap.bitmapData?[4] == 0xFF)
    }

    @Test func ordinaryAndNativeUITestLaunchesKeepTheirOwnIcon() {
        var installs = 0
        for (hosted, uiTesting) in [(false, false), (false, true), (true, true)] {
            #expect(!ComponentTestHostPresentation.isRequired(isTestHost: hosted, isUITesting: uiTesting))
            ComponentTestHostPresentation.installIconIfRequired(isTestHost: hosted, isUITesting: uiTesting) { _ in
                installs += 1
            }
        }
        #expect(installs == 0)
        #expect(ComponentTestHostPresentation.isRequired(isTestHost: true, isUITesting: false))
    }

    @Test func actualComponentHostHasTheOwnedBitmapInstalled() throws {
        #expect(SingleTestInstanceGuard.isRunningUnderXCTest)
        let image = try #require(NSApplication.shared.applicationIconImage)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        #expect(bitmap.pixelsWide == 16 && bitmap.pixelsHigh == 16)
        let black = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        let white = try #require(bitmap.colorAt(x: 1, y: 0)?.usingColorSpace(.sRGB))
        #expect(black.redComponent < 0.01 && black.greenComponent < 0.01 && black.blueComponent < 0.01)
        #expect(white.redComponent > 0.99 && white.greenComponent > 0.99 && white.blueComponent > 0.99)
        #expect(black.alphaComponent > 0.99 && white.alphaComponent > 0.99)
    }

    @Test func componentDocumentProxyRetainsAndClearsItsValue() {
        let window = DocumentWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        defer { window.close() }
        #expect(window.usesComponentDocumentProxyFixture)
        let initialAssignments = window.componentProxyAssignmentCount
        let url = URL(fileURLWithPath: "/private/tmp/component-proxy-\(UUID().uuidString).md")
        window.documentRepresentedURL = url
        #expect(window.documentRepresentedURL == url)
        #expect(window.representedURL == nil, "the component fixture does not create a native proxy")
        #expect(window.componentProxyAssignmentCount == initialAssignments + 1)
        window.documentRepresentedURL = nil
        #expect(window.documentRepresentedURL == nil)
        #expect(window.componentProxyAssignmentCount == initialAssignments + 2)
    }
}
