import XCTest

@MainActor
final class ExternalFileChangesUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDirectory: URL!
    private var fixtureURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
        fixtureURL = sessionDirectory.appendingPathComponent("external.md")
        try? "# Original\n".write(to: fixtureURL, atomically: true, encoding: .utf8)
        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDirectory.path,
            "-openFiles", fixtureURL.path,
        ]
        #if ISSUE117_NATIVE_ACCEPTANCE
            app.launchArguments.insert("-Issue117Acceptance", at: 0)
        #endif
        let fixtureHome = sessionDirectory.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
        app.launchEnvironment["CFFIXED_USER_HOME"] = fixtureHome.path
    }

    override func tearDown() async throws {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDirectory)
    }

    /// `app.otherElements[id]` requires the AX element to have the exact
    /// `XCUIElementTypeOther` role, but `.accessibilityElement(children:)`
    /// (`.combine`/`.contain` — needed so these banners' own identifiers
    /// attach reliably rather than leaking their ancestor's, see
    /// `ExternalFileStatusView.swift`) produces a `Group`-typed element
    /// instead, confirmed via a real accessibility-tree dump. Matching by
    /// identifier alone, regardless of type, is the robust form other
    /// UI-test files in this target already use.
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testCleanExternalReplacementReloadsWithoutAConflictSheet() {
        app.launch()
        app.activate()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        atomicallyReplaceFixture(with: "# Disk Version\n")

        let reload = element("externalReloadStatus")
        XCTAssertTrue(reload.waitForExistence(timeout: 8))
        XCTAssertEqual(textView.value as? String, "# Disk Version\n")
        XCTAssertFalse(element("externalChangeBanner").exists)
    }

    func testDirtyExternalReplacementKeepsLocalTextUntilDiskVersionIsChosen() {
        app.launch()
        app.activate()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeText("local edit")

        atomicallyReplaceFixture(with: "# New Disk Version\n")

        let banner = element("externalChangeBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["externalConflictNotNowButton"].exists)
        app.buttons["externalConflictNotNowButton"].click()
        XCTAssertTrue(banner.exists)

        app.buttons["externalConflictUseDiskButton"].click()
        XCTAssertTrue(waitForText(in: textView, equalTo: "# New Disk Version\n"))
        XCTAssertFalse(banner.exists)
    }

    func testKeepMyChangesDismissesConflictAndPreservesEditorText() {
        app.launch()
        app.activate()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeText(" local edit")
        atomicallyReplaceFixture(with: "# Disk Version\n")

        let banner = element("externalChangeBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        app.buttons["externalConflictKeepMineButton"].click()

        XCTAssertTrue(waitForText(in: textView, equalTo: "# Original\n local edit"))
        XCTAssertTrue(waitForDisappearance(of: banner))
    }

    func testCancelThenUseDiskRevalidatesAgainstTheLatestDiskVersion() {
        app.launch()
        app.activate()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeText(" local edit")
        atomicallyReplaceFixture(with: "# First Disk Version\n")

        let banner = element("externalChangeBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        app.buttons["externalConflictNotNowButton"].click()
        XCTAssertTrue(banner.exists)

        // Use Disk Version obtains a fresh monitor snapshot. Replacing the
        // fixture after Cancel verifies that the action uses that latest
        // snapshot rather than the originally presented conflict revision.
        atomicallyReplaceFixture(with: "# Latest Disk Version\n")
        app.buttons["externalConflictUseDiskButton"].click()

        XCTAssertTrue(waitForText(in: textView, equalTo: "# Latest Disk Version\n"))
        XCTAssertTrue(waitForDisappearance(of: banner))
    }

    func testUseDiskResolutionShowsUnavailableStateWhenBackingFileVanishes() {
        // The monitor's default 150 ms debounce notices the deletion below
        // before XCUITest's click lands (~300 ms), replacing the conflict
        // banner — and its Use Disk Version button — with the unavailable
        // banner, so the click never reached `resolveConflict(.useExternal)`.
        // A 3 s debounce makes the click land first, so this exercises the
        // Use-Disk-Version path's own "backing file vanished" handling.
        app.launchArguments += ["-fileMonitorDebounceMs", "3000"]
        app.launch()
        app.activate()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeText(" local edit")
        atomicallyReplaceFixture(with: "# Disk Version\n")

        let banner = element("externalChangeBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        try? FileManager.default.removeItem(at: fixtureURL)
        app.buttons["externalConflictUseDiskButton"].click()

        XCTAssertTrue(app.buttons["externalBackingSaveAsButton"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForText(in: textView, equalTo: "# Original\n local edit"))
    }

    func testConflictCloseUseDiskClosesWithoutDiscardingTheExternalVersion() {
        app.launch()
        app.activate()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeText(" local edit")
        atomicallyReplaceFixture(with: "# Disk Version Chosen At Close\n")

        let conflict = element("externalChangeBanner")
        XCTAssertTrue(conflict.waitForExistence(timeout: 8))
        app.typeKey("w", modifierFlags: .command)

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let useDisk = sheet.buttons["Use Disk Version and Close"]
        XCTAssertTrue(useDisk.waitForExistence(timeout: 3))
        useDisk.click()

        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: textView)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(
            try? String(contentsOf: fixtureURL, encoding: .utf8),
            "# Disk Version Chosen At Close\n"
        )
    }

    private func atomicallyReplaceFixture(with text: String) {
        let replacement = fixtureURL.deletingLastPathComponent()
            .appendingPathComponent("replacement-\(UUID().uuidString).md")
        try? text.write(to: replacement, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.replaceItemAt(fixtureURL, withItemAt: replacement)
    }

    private func waitForText(in textView: XCUIElement, equalTo expected: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: textView)
        return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
    }

    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
    }
}
