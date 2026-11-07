import AppKit
import CryptoKit
import Darwin
import XCTest

@MainActor
extension PublicFocusTests {
    @objc func testNormalFutureSessionBlocksOrdinaryEditing() throws {
        let root = URL(fileURLWithPath: HostedFocusInputs.identity).deletingLastPathComponent()
        let record = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("current-application.json"))
        ) as? [String: Any])
        let pid = try XCTUnwrap((record["pid"] as? NSNumber)?.int32Value)
        let running = try XCTUnwrap(NSRunningApplication(processIdentifier: pid))
        XCTAssertEqual(running.bundleIdentifier, "app.mostlytext.MostlyText")
        XCTAssertEqual(running.executableURL?.resolvingSymlinksInPath().path, HostedFocusInputs.executable)
        XCTAssertEqual(running.bundleURL?.resolvingSymlinksInPath().path, HostedFocusInputs.application)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: HostedFocusInputs.executable))
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                       HostedFocusInputs.appSHA256)
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        app.activate()
        defer {
            let tree = XCTAttachment(string: String(app.debugDescription.prefix(131_072)))
            tree.name = "Normal future session: actual blocked migration surface"
            tree.lifetime = .keepAlways
            add(tree)
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "Unsupported future session remains blocked"
            screen.lifetime = .keepAlways
            add(screen)
        }
        let window = app.windows["MostlyText Migration"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Installation Needs Review"].waitForExistence(timeout: 5))
        for title in ["Quit", "Retry Migration"] {
            let button = window.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(button.isEnabled)
        }
        XCTAssertEqual(app.tabs.count, 0)
        XCTAssertEqual(app.textViews.count, 0)
        XCTAssertFalse(app.windows["Welcome to MostlyText"].exists)
        XCTAssertFalse(app.buttons["Continue With Existing Installation"].exists)
        XCTAssertFalse(app.windows.matching(NSPredicate(format: "title CONTAINS %@", "snippets.json"))
            .firstMatch.exists)
        XCTAssertEqual(NSRunningApplication(processIdentifier: pid)?.executableURL?.resolvingSymlinksInPath().path,
                       HostedFocusInputs.executable)
    }
}
