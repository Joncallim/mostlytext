import AppKit
import XCTest

@MainActor
final class ColdFinderTests: XCTestCase {
    func testActualColdFinderStaticReply() throws {
        continueAfterFailure = false
        XCTAssertEqual(FileManager.default.homeDirectoryForCurrentUser.path, "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty,
                      "The containing fixture must not launch before cold Finder")
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.windows.firstMatch.waitForExistence(timeout: 10))
        let fileName = "mostlytext-ql-reply-static.md"
        let file = finder.descendants(matching: .any).matching(identifier: fileName).firstMatch
        let named = finder.staticTexts[fileName].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists,
                      "The generated file must be visible in real Finder before invoking Quick Look")
        if file.exists { file.click() } else { named.click() }
        finder.typeKey(.space, modifierFlags: [])
        let marker = finder.staticTexts["MOSTLYTEXT_QL_REPLY_STATIC_20261107"].firstMatch
        let visible = marker.waitForExistence(timeout: 15)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65_536)))
        tree.name = "Actual Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual Finder after Quick Look invocation"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible,
                      "Require the actual provider marker through Finder; no mock/qlmanage substitution")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty,
                      "No containing app launch is permitted to manufacture a cold preview")
        finder.typeKey(.escape, modifierFlags: [])
    }
}
