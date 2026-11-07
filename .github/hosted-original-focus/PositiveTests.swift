import AppKit
import Darwin
import XCTest

@MainActor
final class OriginalFocusPositiveTests: XCTestCase {
    func testActualTypingAndButtonBeforeOriginalAppCase() throws {
        continueAfterFailure = false
        XCTAssertEqual(getuid(), geteuid())
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        XCTAssertEqual(FileManager.default.homeDirectoryForCurrentUser.path,
                       "/Users/runner/Library/Containers/app.mostlytext.HostedFocus.Driver.xctrunner/Data")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)
        let control = XCUIApplication()
        control.launch()
        defer {
            control.terminate()
            XCTAssertTrue(control.wait(for: .notRunning, timeout: 5))
        }
        let window = control.windows["MostlyText hosted input control"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let field = window.textFields["positiveTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        field.click()
        field.typeText("Original42")
        XCTAssertEqual(field.value as? String, "Original42")
        let button = window.buttons["positiveButton"]
        XCTAssertTrue(button.isHittable)
        let counter = window.staticTexts["positiveCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.value as? String ?? counter.label, "0")
        button.click()
        XCTAssertEqual(counter.value as? String ?? counter.label, "1")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Actual original-focus benign input control"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
