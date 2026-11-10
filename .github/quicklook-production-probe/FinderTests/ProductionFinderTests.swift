import AppKit
import Darwin
import XCTest

@MainActor
final class ProductionFinderTests: XCTestCase {
    func testInstalledProductionProviderShowsSelectedMarkdownSource() throws {
        continueAfterFailure = false
        XCTAssertEqual(getuid(), geteuid())
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.windows.firstMatch.waitForExistence(timeout: 10))
        let fileName = "mostlytext-production-quicklook.md"
        let file = finder.descendants(matching: .any).matching(identifier: fileName).firstMatch
        let named = finder.staticTexts[fileName].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists)
        if file.exists { file.click() } else { named.click() }
        finder.typeKey(.space, modifierFlags: [])

        let marker = finder.staticTexts["MOSTLYTEXT_PRODUCTION_QUICKLOOK_20261111"].firstMatch
        let visible = marker.waitForExistence(timeout: 15)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65_536)))
        tree.name = "Production Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Production Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The actual product extension must answer Finder with selected source")
        let open = finder.buttons["QLControlOpen"].firstMatch
        XCTAssertEqual(open.title, "Open with MostlyText")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }
}
