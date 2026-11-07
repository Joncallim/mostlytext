import AppKit
import CryptoKit
import Darwin
import XCTest

@MainActor
extension PublicFocusTests {
    @objc func testNormalDevelopmentProfileAdoption() throws {
        try requireMigratedProfile(indentation: 2)
    }

    @objc func testNormalMigratedProfileRelaunch() throws {
        try requireMigratedProfile(indentation: 8)
    }

    private func requireMigratedProfile(indentation: Int) throws {
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
        let seed = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("migration-seed.json"))
        ) as? [String: Any])
        let recovered = try XCTUnwrap(seed["unsavedText"] as? String)
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        app.activate()
        defer { captureMigration(app, indentation: indentation) }
        let external = app.tabs.matching(NSPredicate(format: "title CONTAINS %@", "migration-external.txt"))
        let managed = app.tabs.matching(NSPredicate(format: "title CONTAINS %@", "snippets.json"))
        XCTAssertTrue(external.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(managed.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(external.count, 1)
        XCTAssertEqual(managed.count, 1)
        XCTAssertEqual(app.tabs.count, 2, "Only the two seeded native tabs may restore")
        let selected = app.tabs.matching(NSPredicate(format: "value == %d AND title CONTAINS %@", 1, "snippets.json"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 5))
        let window = app.windows.matching(NSPredicate(format: "title CONTAINS %@", "snippets.json")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let editor = window.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let text = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", recovered), object: editor)
        XCTAssertEqual(XCTWaiter().wait(for: [text], timeout: 5), .completed)
        let status = window.staticTexts["statusBarIndentation"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String ?? status.label, "Spaces: \(indentation)")
        XCTAssertFalse(app.staticTexts["Installation Needs Review"].exists)
        XCTAssertFalse(app.buttons["Retry Migration"].exists)
        XCTAssertFalse(app.buttons["Continue With Existing Installation"].exists)
        XCTAssertFalse(app.windows["Welcome to MostlyText"].exists)
        XCTAssertFalse(app.buttons["Import Settings"].exists)
        XCTAssertEqual(NSRunningApplication(processIdentifier: pid)?.executableURL?.resolvingSymlinksInPath().path,
                       HostedFocusInputs.executable)
    }

    private func captureMigration(_ app: XCUIApplication, indentation: Int) {
        let tree = XCTAttachment(string: String(app.debugDescription.prefix(131_072)))
        tree.name = "Normal migrated profile with indentation \(indentation)"
        tree.lifetime = .keepAlways
        add(tree)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "Actual migrated native tabs and recovery \(indentation)"
        screen.lifetime = .keepAlways
        add(screen)
    }
}
