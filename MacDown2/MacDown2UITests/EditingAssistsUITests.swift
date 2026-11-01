import Darwin
import XCTest

/// E10 smoke coverage through the real app: Return-key list continuation in
/// Markdown, and no synthetic pairing in non-Markdown formats.
@MainActor
final class EditingAssistsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!
    private var isolatedRunDir: URL?
    private var didAttemptLaunch = false
    private var didLaunchApp = false

    override func setUp() async throws {
        continueAfterFailure = false
        #if UITEST_ISOLATED
            let owner = try XCTUnwrap(ProcessInfo.processInfo.environment["MOSTLYTEXT_UI_TEST_OWNER_UID"])
            guard let ownerUID = uid_t(owner), ownerUID > 0,
                  getuid() == geteuid(), geteuid() != 0, geteuid() != ownerUID else {
                throw NSError(domain: "UITestIsolation", code: 4)
            }
            let bundleID = try XCTUnwrap(ProcessInfo.processInfo.environment["MOSTLYTEXT_UI_TEST_BUNDLE_ID"])
            let prefix = "com.joncallim.MacDown2.UITestIsolated."
            guard bundleID.hasPrefix(prefix), UUID(uuidString: String(bundleID.dropFirst(prefix.count))) != nil else {
                throw NSError(domain: "UITestIsolation", code: 1)
            }
            app = XCUIApplication(bundleIdentifier: bundleID)
            let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
            guard length > 1 else { throw NSError(domain: "UITestIsolation", code: 2) }
            var buffer = [CChar](repeating: 0, count: length)
            guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) == length else {
                throw NSError(domain: "UITestIsolation", code: 3)
            }
            let root = URL(fileURLWithPath: String(cString: buffer), isDirectory: true).resolvingSymlinksInPath()
            let runID = String(bundleID.dropFirst(prefix.count))
            let runDir = root.appendingPathComponent("MostlyTextUITest-" + runID, isDirectory: true)
            guard mkdir(runDir.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            isolatedRunDir = runDir
        #else
            app = XCUIApplication()
        #endif

        #if UITEST_ISOLATED
            fixturesDir = try XCTUnwrap(isolatedRunDir).appendingPathComponent("fixtures", isDirectory: true)
        #else
            fixturesDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        #endif
        try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        let markdownFile = fixturesDir.appendingPathComponent("a.md")
        // No trailing newline: the initial caret lands at the end of the
        // single list line, exactly where Return must continue the list.
        try "- item".write(to: markdownFile, atomically: true, encoding: .utf8)
        let plainFile = fixturesDir.appendingPathComponent("a.txt")
        try "".write(to: plainFile, atomically: true, encoding: .utf8)

        #if UITEST_ISOLATED
            sessionDir = try XCTUnwrap(isolatedRunDir).appendingPathComponent("session", isDirectory: true)
        #else
            sessionDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        #endif
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-openFiles", "\(markdownFile.path),\(plainFile.path)",
        ]
    }

    override func tearDown() async throws {
        // A failed launch can still leave a process alive. Preserve its files
        // when ownership or termination cannot be established.
        if didAttemptLaunch, !didLaunchApp {
            return
        }
        if didLaunchApp {
            app.terminate()
            guard app.wait(for: .notRunning, timeout: 5) else { return }
        }
        if let sessionDir {
            try? FileManager.default.removeItem(at: sessionDir)
        }
        if let fixturesDir {
            try? FileManager.default.removeItem(at: fixturesDir)
        }
        if let isolatedRunDir {
            try? FileManager.default.removeItem(at: isolatedRunDir)
        }
    }

    private func launchTestApp() {
        didAttemptLaunch = true
        app.launch()
        didLaunchApp = true
    }

    /// Select by fixture identity: native tab order and initial selection can
    /// vary when multiple documents are opened at launch. Confirm the active
    /// tab before sending keystrokes so a misdirected edit cannot pass.
    private func selectTab(named name: String) {
        let tab = app.tabs.matching(NSPredicate(format: "title == %@", name)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab \(name)")
        tab.click()
        let selected = app.tabs.matching(NSPredicate(format: "title == %@ AND value == %d", name, 1)).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5), "Tab did not become active: \(name)")
    }

    /// Waits (2 s, the bound the Focus Outline step always used) for a menu
    /// item's enablement to reach `enabled`. SwiftUI publishes a command's
    /// `.disabled` state to its `NSMenuItem` on its next update pass, not
    /// synchronously with the focus change: logging showed
    /// `canPerformMarkdownEditingCommand` already `true` while XCUITest still
    /// read the item as disabled, then enabled on the next sample. A missing
    /// command is not evidence that it is disabled.
    private func waitFor(_ item: XCUIElement, enabled: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND enabled == %@", NSNumber(value: enabled)),
            object: item
        )
        return XCTWaiter().wait(for: [expectation], timeout: 2) == .completed
    }

    func testListContinuationOnReturn() {
        launchTestApp()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(named: "a.md")

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()

        // The fixture is "- item" and the caret is at its end; pressing
        // Return must continue the unordered list.
        app.typeKey(.return, modifierFlags: [])

        let expected = "- item\n- "
        let predicate = NSPredicate { _, _ in
            (textView.value as? String)?.hasSuffix(expected) == true
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)

        // Normal input continues after the handled Return.
        textView.typeText("next")
        XCTAssertTrue((textView.value as? String)?.hasSuffix("- next") == true)
    }

    /// EPIC-22 Slice 4a (#140) made structural bracket/quote pairing a
    /// general, every-format assist, so "(" → "()" is now correct in plain
    /// text too. What must still never fire outside Markdown is E10's own
    /// Markdown delimiter pairing (`*`, `_`, backtick).
    func testNoMarkdownDelimiterPairingInPlainText() {
        launchTestApp()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let plainTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.txt")).firstMatch
        XCTAssertTrue(plainTab.waitForExistence(timeout: 5))
        selectTab(named: "a.txt")

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // E10's Markdown delimiters stay lone characters outside Markdown…
        textView.click()
        textView.typeText("*_`")
        XCTAssertEqual(textView.value as? String ?? "", "*_`")

        // …while the general structural pairing still applies here.
        textView.typeText("(")
        XCTAssertEqual(textView.value as? String ?? "", "*_`()")
    }

    /// The Format menu's Markdown commands must be reachable while the editor
    /// is focused: the menu item enables (first-responder identity) and the
    /// click applies through the same one-edit command bridge as ⌘B.
    func testBoldMenuCommandAppliesToFocusedEditor() {
        launchTestApp()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(named: "a.md")

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()

        app.menuBars.menuBarItems["Format"].click()
        let boldItem = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(boldItem.waitForExistence(timeout: 5))
        XCTAssertTrue(boldItem.isEnabled, "Bold must be enabled while the Markdown editor is focused")

        boldItem.click()

        // The fixture is "- item" with the caret at its end; Bold on an empty
        // selection inserts the empty `**` delimiters with the caret inside.
        XCTAssertTrue((textView.value as? String)?.hasSuffix("****") == true)
    }

    /// Command validation follows the real responder chain: moving focus to
    /// the sidebar or Find field disables formatting, and returning to the
    /// editor re-enables it. The action is also guarded independently so a
    /// stale menu update cannot edit the wrong responder.
    func testFormattingMenuTracksEditorSidebarFindAndEditorFocus() {
        launchTestApp()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(named: "a.md")

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let boldItem = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // A sidebar control that really takes keyboard focus. The folder
        // section's "No folder opened" placeholder this used to click centers
        // on its "Open Folder…" button, which (like any macOS button without
        // Full Keyboard Access) never becomes first responder — the editor
        // kept focus, so Bold correctly stayed enabled.
        let sidebarSearchField = app.textFields["folderSearchField"]
        XCTAssertTrue(sidebarSearchField.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarSearchField.isHittable, "Sidebar focus target must be interactable")
        sidebarSearchField.click()
        XCTAssertTrue(waitFor(boldItem, enabled: false))

        // Back to the editor first, so the Find step below proves its own
        // transition rather than inheriting the sidebar's disabled state.
        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // The app's own Find in Document bar (EPIC-22 Slice 5a; ⌘F). Not
        // `app.searchFields.firstMatch`: that only ever matched the Help menu's always-present search field.
        app.typeKey("f", modifierFlags: .command)
        let findField = app.textFields["findBarQueryField"]
        XCTAssertTrue(findField.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(boldItem, enabled: false))
        // The bar really took keyboard focus: typing goes to its query, not
        // into the document.
        app.typeText("zz")
        XCTAssertEqual(findField.value as? String, "zz")
        XCTAssertEqual(textView.value as? String, "- item")
        app.typeKey(.escape, modifierFlags: [])

        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))
    }

    /// The standard ⌘F opens the docked Find in Document bar and focuses its query field (owner decision: it used to
    /// do nothing in the editor).
    func testCommandFOpensTheFindBar() {
        launchTestApp()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        selectTab(named: "a.md")
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let findField = app.textFields["findBarQueryField"]

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 5), "⌘F must open the Find bar")
        app.typeText("zz")
        XCTAssertEqual(findField.value as? String, "zz", "the bar took keyboard focus")
        XCTAssertEqual(textView.value as? String, "- item", "typing did not reach the document")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(findField), "Escape closes the bar")
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func testFormattingMenuRefreshesAfterKeyboardTabAndFocusOutline() {
        launchTestApp()
        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let markdownTab = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        XCTAssertTrue(markdownTab.waitForExistence(timeout: 5))
        selectTab(named: "a.md")

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        let boldItem = app.menuBars.menuBarItems["Format"].menuItems["Bold"].firstMatch
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // Native tab navigation changes the active editor/responder without
        // generating ordinary typing events.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(waitFor(boldItem, enabled: false))
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))

        // Focus Outline is a coordinator-owned programmatic focus transition.
        app.typeKey("o", modifierFlags: [.control, .command])
        XCTAssertTrue(waitFor(boldItem, enabled: false))
        textView.click()
        XCTAssertTrue(waitFor(boldItem, enabled: true))
    }
}
