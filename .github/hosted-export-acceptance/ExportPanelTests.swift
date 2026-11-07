import AppKit
import CryptoKit
import Darwin
import XCTest

@MainActor
final class ExportPanelTests: XCTestCase {
    func testNormalExportSaveAndCancel() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let identity = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: HostedFocusInputs.identity))
        )
        let record = try XCTUnwrap(identity as? [String: Any])
        let pid = try XCTUnwrap((record["pid"] as? NSNumber)?.int32Value)
        let running = try XCTUnwrap(NSRunningApplication(processIdentifier: pid))
        XCTAssertEqual(running.bundleIdentifier, "app.mostlytext.MostlyText")
        XCTAssertEqual(running.bundleURL?.resolvingSymlinksInPath().path, HostedFocusInputs.application)
        XCTAssertEqual(try digest(HostedFocusInputs.executable), HostedFocusInputs.appSHA256)
        XCTAssertEqual(running.executableURL?.resolvingSymlinksInPath().path, HostedFocusInputs.executable)
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        app.activate()
        defer { capture(app, label: "Ordinary Release export final state") }
        let matches = app.windows.matching(NSPredicate(format: "title CONTAINS %@", HostedFocusInputs.fileName))
        let window = matches.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(matches.count, 1)
        let editor = window.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("NATIVE_EXPORT_CANARY") == true)
        editor.click()
        XCTAssertFalse(FileManager.default.fileExists(atPath: HostedExportInputs.html))
        XCTAssertFalse(FileManager.default.fileExists(atPath: HostedExportInputs.pdf))
        let cancelled = openPanel(app, window: window)
        capture(app, label: "Actual ordinary Export panel before Cancel")
        cancelled.buttons["Cancel"].click()
        XCTAssertTrue(cancelled.waitForNonExistence(timeout: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: HostedExportInputs.html))
        XCTAssertFalse(FileManager.default.fileExists(atPath: HostedExportInputs.pdf))
        try export(app, window: window, format: "HTML", destination: HostedExportInputs.html)
        app.activate()
        editor.click()
        try export(app, window: window, format: "PDF", destination: HostedExportInputs.pdf)
        XCTAssertEqual(try digest(HostedExportInputs.source), HostedExportInputs.sourceSHA256)
        XCTAssertEqual(NSRunningApplication(processIdentifier: pid)?.executableURL?.resolvingSymlinksInPath().path,
                       HostedFocusInputs.executable)
    }

    private func openPanel(_ app: XCUIApplication, window: XCUIElement) -> XCUIElement {
        app.menuBars.menuBarItems["File"].click()
        let command = app.menuBars.menuBarItems["File"].menuItems["Export…"].firstMatch
        XCTAssertTrue(command.isEnabled)
        command.click()
        let panel = window.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.buttons["Export"].exists)
        return panel
    }

    private func export(_ app: XCUIApplication, window: XCUIElement, format: String, destination: String) throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
        let panel = openPanel(app, window: window)
        let choice = panel.radioButtons[format].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.click()
        let suffix = format == "PDF" ? "pdf" : "html"
        let expected = (HostedFocusInputs.fileName as NSString).deletingPathExtension + "." + suffix
        let fields = panel.textFields.matching(NSPredicate(format: "value == %@", expected))
        XCTAssertEqual(fields.count, 1, "Require the actual unique filename field with the source-derived default")
        let name = fields.firstMatch
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText((destination as NSString).lastPathComponent)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(HostedFocusInputs.folder)
        app.typeKey(.return, modifierFlags: [])
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND hittable == YES"), object: panel.buttons["Export"]
        )
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed)
        capture(app, label: "Actual ordinary " + format + " Export before save")
        panel.buttons["Export"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while !FileManager.default.fileExists(atPath: destination), ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destination),
            "Actual UI export must publish its expected file"
        )
        let bytes = try Data(contentsOf: URL(fileURLWithPath: destination))
        XCTAssertGreaterThan(bytes.count, 0)
        XCTAssertLessThan(bytes.count, 16 * 1024 * 1024)
        XCTAssertEqual(try digest(HostedExportInputs.source), HostedExportInputs.sourceSHA256)
        capture(app, label: "Actual ordinary " + format + " Export after save")
    }

    private func digest(_ path: String) throws -> String {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func capture(_ app: XCUIApplication, label: String) {
        let tree =
            XCTAttachment(string: "uptime=\(ProcessInfo.processInfo.systemUptime)\n" +
                String(app.debugDescription.prefix(131_072)))
        tree.name = label + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = label + " screenshot"
        screen.lifetime = .keepAlways
        add(screen)
    }
}
