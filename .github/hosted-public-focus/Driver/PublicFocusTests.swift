import AppKit
import CryptoKit
import Darwin
import XCTest

@MainActor
final class PublicFocusTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCTAssertEqual(getuid(), geteuid())
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(FileManager.default.homeDirectoryForCurrentUser.path,
                       "/Users/runner/Library/Containers/app.mostlytext.HostedFocus.Driver.xctrunner/Data")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
    }

    func testBenignInputControl() throws {
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)
        let control = XCUIApplication()
        control.launch()
        defer {
            control.terminate()
            XCTAssertTrue(control.wait(for: .notRunning, timeout: 5))
        }
        let window = control.windows["MostlyText hosted input control"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        defer { capture(control, label: "Benign input control") }
        let field = window.textFields["positiveTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        field.click()
        field.typeText("Focus42")
        XCTAssertEqual(field.value as? String, "Focus42")
        let button = window.buttons["positiveButton"]
        XCTAssertTrue(button.isHittable)
        button.click()
        let counter = window.staticTexts["positiveCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.value as? String ?? counter.label, "1")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty,
                      "A failed control must never be followed by a product launch")
    }

    /// Normal public behavior corresponding to the protected source tests' focus/Bold cases.
    /// The protected test configuration/executor and its execution hold are unchanged.
    func testNormalPublicFocusBoldAndUndo() throws {
        let identity = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: HostedFocusInputs.identity)))
        let record = try XCTUnwrap(identity as? [String: Any])
        let pid = try XCTUnwrap((record["pid"] as? NSNumber)?.int32Value)
        let running = try XCTUnwrap(NSRunningApplication(processIdentifier: pid))
        XCTAssertEqual(running.bundleIdentifier, "app.mostlytext.MostlyText")
        XCTAssertEqual(running.executableURL?.resolvingSymlinksInPath().path, HostedFocusInputs.executable)
        XCTAssertEqual(running.bundleURL?.resolvingSymlinksInPath().path, HostedFocusInputs.application)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: HostedFocusInputs.executable))
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), HostedFocusInputs.appSHA256)

        // Attach only; the outer, verified controller already performed an ordinary launch.
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        app.activate()
        defer { capture(app, label: "Normal public focus and formatting") }
        let matching = app.windows.matching(NSPredicate(format: "title CONTAINS %@", HostedFocusInputs.fileName))
        let window = matching.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(matching.count, 1, "Every edit must target the unique generated document")
        let editor = window.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "- item")
        editor.click()

        // Obtain a genuine nonempty folder through public UI, without a test launch flag.
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuBarItems["File"].menuItems["Open Folder…"].click()
        let panel = window.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(HostedFocusInputs.folder)
        app.typeKey(.return, modifierFlags: [])
        let open = panel.buttons["Open Folder"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == YES AND hittable == YES"), object: open)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed)
        open.click()
        let row = window.descendants(matching: .any).matching(identifier: "fileRow-" + HostedFocusInputs.fileName).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "- item")

        editor.click()
        expectBold(app, enabled: true)
        let sidebar = window.textFields["folderSearchField"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar.isHittable)
        sidebar.click()
        sidebar.typeText("focus-query")
        XCTAssertEqual(sidebar.value as? String, "focus-query", "Typing must prove actual sidebar focus")
        XCTAssertEqual(editor.value as? String, "- item")
        expectBold(app, enabled: false)
        sidebar.click()
        sidebar.typeKey("a", modifierFlags: .command)
        sidebar.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(sidebar.value as? String, "")
        editor.click()
        expectBold(app, enabled: true)

        app.typeKey("f", modifierFlags: .command)
        let find = window.textFields["findBarQueryField"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        app.typeText("zz")
        XCTAssertEqual(find.value as? String, "zz", "Typing must reach the actual document Find field")
        XCTAssertEqual(editor.value as? String, "- item")
        expectBold(app, enabled: false)
        app.typeKey(.escape, modifierFlags: [])
        editor.click()
        expectBold(app, enabled: true)

        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(.rightArrow, modifierFlags: [])
        app.menuBars.menuBarItems["Format"].click()
        let bold = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(bold.isEnabled)
        bold.click()
        expectValue(editor, "- item****")
        app.typeKey("z", modifierFlags: .command)
        expectValue(editor, "- item")
        XCTAssertEqual(NSRunningApplication(processIdentifier: pid)?.executableURL?.resolvingSymlinksInPath().path,
                       HostedFocusInputs.executable)
    }

    private func expectBold(_ app: XCUIApplication, enabled: Bool) {
        // Reopen/query at every transition; never reuse a lazy menu snapshot.
        app.menuBars.menuBarItems["Format"].click()
        let item = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        let condition = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND enabled == %@", NSNumber(value: enabled)), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [condition], timeout: 2), .completed)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func expectValue(_ element: XCUIElement, _ value: String) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [condition], timeout: 5), .completed)
    }

    private func capture(_ app: XCUIApplication, label: String) {
        let tree = XCTAttachment(string: String(app.debugDescription.prefix(131_072)))
        tree.name = label + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = label + " screenshot"
        screen.lifetime = .keepAlways
        add(screen)
    }
}
