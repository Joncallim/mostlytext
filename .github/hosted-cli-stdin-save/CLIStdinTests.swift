import AppKit
import CryptoKit
import Darwin
import XCTest

@MainActor
final class CLIStdinTests: XCTestCase {
    func testOrdinaryStdinDocumentSavesExactUTF8Bytes() throws {
        continueAfterFailure = false
        try verifyRunner()
        let raw = try JSONSerialization
            .jsonObject(with: Data(contentsOf: URL(fileURLWithPath: HostedFocusInputs.identity)))
        let identity = try XCTUnwrap(raw as? [String: Any])
        let pid = try XCTUnwrap((identity["pid"] as? NSNumber)?.int32Value)
        let birth = try XCTUnwrap((identity["birth"] as? NSNumber)?.doubleValue)
        let running = try XCTUnwrap(NSRunningApplication(processIdentifier: pid))
        XCTAssertEqual(running.launchDate?.timeIntervalSince1970, birth)
        XCTAssertEqual(running.bundleIdentifier, "app.mostlytext.MostlyText")
        XCTAssertEqual(running.bundleURL?.resolvingSymlinksInPath().path, HostedFocusInputs.application)
        XCTAssertEqual(running.executableURL?.resolvingSymlinksInPath().path, HostedFocusInputs.executable)
        let executable = try Data(contentsOf: URL(fileURLWithPath: HostedFocusInputs.executable))
        XCTAssertEqual(
            SHA256.hash(data: executable).map { String(format: "%02x", $0) }.joined(),
            HostedFocusInputs.appSHA256
        )
        let oracle = try Data(contentsOf: URL(fileURLWithPath: CLIStdinInputs.oracle))
        let expected = try XCTUnwrap(String(data: oracle, encoding: .utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CLIStdinInputs.saved))

        // Attach only after the controller bound the existing normal launch.
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        app.activate()
        defer { capture(app, name: "CLI stdin and native save actual final state") }
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .map(\.processIdentifier), [pid])
        XCTAssertFalse(running.isTerminated)
        let documents = app.windows.allElementsBoundByIndex.filter { window in
            window.textViews.count == 1 && (window.textViews.firstMatch.value as? String)
                .map { Array($0.utf8) } == Array(expected.utf8)
        }
        XCTAssertEqual(documents.count, 1, "Exactly one actual document must contain the complete stdin bytes")
        let window = try XCTUnwrap(documents.first)
        let editor = window.textViews.firstMatch
        XCTAssertEqual(try Array(XCTUnwrap(editor.value as? String).utf8), Array(oracle))
        XCTAssertTrue(editor.isHittable)
        editor.click()
        saveDocument(app, window: window)
        let saved = app.windows.matching(NSPredicate(format: "title CONTAINS %@", "cli-saved-stdin.md"))
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(try Array(XCTUnwrap(saved.firstMatch.textViews.firstMatch.value as? String).utf8), Array(oracle))
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .map(\.processIdentifier), [pid])
        XCTAssertFalse(running.isTerminated)
        XCTAssertEqual(running.launchDate?.timeIntervalSince1970, birth)
        capture(app, name: "CLI stdin physical save completed")
    }

    private func verifyRunner() throws {
        XCTAssertEqual(getuid(), geteuid())
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(FileManager.default.homeDirectoryForCurrentUser.path,
                       "/Users/runner/Library/Containers/app.mostlytext.HostedFocus.Driver.xctrunner/Data")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
    }

    private func saveDocument(_ app: XCUIApplication, window: XCUIElement) {
        app.typeKey("s", modifierFlags: [.command, .shift])
        let panel = window.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        defer { capture(app, name: "CLI stdin Save panel and document tree") }
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(CLIStdinInputs.folder)
        app.typeKey(.return, modifierFlags: [])
        let name = panel.textFields["saveAsNameTextField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.isHittable)
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("cli-saved-stdin.md")
        XCTAssertEqual(name.value as? String, "cli-saved-stdin.md")
        let save = panel.buttons["Save"]
        XCTAssertTrue(save.isHittable)
        save.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: panel)
        XCTAssertEqual(XCTWaiter().wait(for: [dismissed], timeout: 5), .completed)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name
        screen.lifetime = .keepAlways
        add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
