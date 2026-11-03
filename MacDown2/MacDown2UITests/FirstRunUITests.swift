import XCTest

/// Real UI-test execution for the E15 first-run welcome screen. `-UITesting`
/// alone always uses a fresh, isolated `UserDefaults` suite that never
/// reports first-run as complete, which would show this window in every one
/// of this target's other UI tests — `-ForceFirstRun` opts in explicitly so
/// only these tests exercise it (see `AppDelegate.init`'s doc comment).
@MainActor
final class FirstRunUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-ForceFirstRun",
        ]
    }

    override func tearDown() async throws {
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    /// `.accessibilityElement(children: .contain)` exposes the welcome view
    /// as a `Group`, not `XCUIElementTypeOther`, so it is matched by
    /// identifier regardless of type — the same form
    /// `ExternalFileChangesUITests.element(_:)` uses.
    private var welcomeView: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "firstRunWelcomeView").firstMatch
    }

    func testStartWritingDismissesWelcomeAndOpensAnEmptyDocument() {
        app.launch()
        app.activate()

        let welcome = welcomeView
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))

        app.buttons["firstRunStartWritingButton"].click()

        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(welcome.exists)
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "")
        assertNoSecondDocumentAppears()
    }

    func testOpenSampleDocumentDismissesWelcomeAndOpensTheSampleText() {
        app.launch()
        app.activate()

        let welcome = welcomeView
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))

        app.buttons["firstRunOpenSampleButton"].click()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        XCTAssertFalse(welcome.exists)
        let sampleText = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Welcome to MostlyText"),
            object: textView
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sampleText], timeout: 5), .completed)
        assertNoSecondDocumentAppears()
        XCTAssertTrue((textView.value as? String)?.contains("Welcome to MostlyText") == true)
    }

    /// The welcome choice opens the only document: the normal launch that
    /// follows dismissal (session restore after its 200 ms grace delay) must
    /// not add a second, untitled tab in front of it. The native tab bar —
    /// hidden for a single tab — would otherwise list two tabs.
    private func assertNoSecondDocumentAppears() {
        let secondTab = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 1"),
            object: app.tabs
        )
        secondTab.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [secondTab], timeout: 2), .completed)
    }
}
