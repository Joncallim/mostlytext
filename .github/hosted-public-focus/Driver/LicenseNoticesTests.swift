import AppKit
import Foundation
import XCTest

@MainActor
extension PublicFocusTests {
    @objc func testNormalBundledLicensesAreReadableAndSearchable() throws {
        try testNormalPublicFocusBoldAndUndo()
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        defer { captureLicenses(app) }
        let product = try licenseOracle("LICENSE")
        let notices = try licenseOracle("THIRD_PARTY_NOTICES.md")
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuBarItems["Help"].menuItems["Open Source Licenses…"].click()
        let window = app.windows["Open Source Licenses"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertFalse(window.descendants(matching: .any).matching(identifier: "licenses.loadFailure").firstMatch
            .exists)
        let content = window.textViews.matching(identifier: "licenses.content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        try requireLicenseCopy(product, app: app, content: content)
        window.radioButtons["Third-party notices"].click()
        try requireLicenseCopy(notices, app: app, content: content)
        try requireNativeLicenseFind(app, content: content, notices: notices)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        app.menuBars.menuBarItems["MostlyText"].click()
        app.menuBars.menuBarItems["MostlyText"].menuItems["About MostlyText"].click()
        let about = app.windows["About MostlyText"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.buttons["about.openSourceLicenses"].click()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(content.waitForExistence(timeout: 5))
    }

    private func licenseOracle(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: HostedFocusInputs.folder).deletingLastPathComponent()
        let file = root.appendingPathComponent("license-oracles").appendingPathComponent(name)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let bytes = try XCTUnwrap(handle.read(upToCount: 2 * 1024 * 1024 + 1))
        XCTAssertLessThanOrEqual(bytes.count, 2 * 1024 * 1024)
        XCTAssertFalse(bytes.isEmpty)
        return try XCTUnwrap(String(data: bytes, encoding: .utf8))
    }

    private func requireLicenseCopy(_ text: String, app: XCUIApplication, content: XCUIElement) throws {
        XCTAssertTrue(waitForLicensePublication { content.value as? String == text })
        XCTAssertTrue(content.isHittable)
        content.click()
        NSPasteboard.general.clearContents()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(waitForLicensePublication { NSPasteboard.general.string(forType: .string) == text },
                      "Real keyboard Copy must publish the complete canonical text")
        XCTAssertEqual(content.value as? String, text)
    }

    private func requireNativeLicenseFind(_ app: XCUIApplication, content: XCUIElement, notices: String) throws {
        app.typeKey("f", modifierFlags: .command)
        let panel = app.dialogs["Find"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let query = panel.comboBoxes["_NS:167"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.click()
        app.typeKey("a", modifierFlags: .command)
        query.typeText("Graphviz")
        XCTAssertEqual(query.value as? String, "Graphviz")
        panel.buttons["Next"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        NSPasteboard.general.clearContents()
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(waitForLicensePublication {
            NSPasteboard.general.string(forType: .string)?.lowercased() == "graphviz"
        }, "Native Find must select the matched notice text for actual Copy")
        XCTAssertEqual(content.value as? String, notices)
    }

    private func waitForLicensePublication(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if predicate() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return predicate()
    }

    private func captureLicenses(_ app: XCUIApplication) {
        let hierarchy = XCTAttachment(string: String(app.debugDescription.prefix(131_072)))
        hierarchy.name = "Actual public licence window and keyboard state"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Actual public licence window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
