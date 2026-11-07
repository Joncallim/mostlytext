import XCTest

@MainActor
final class TabLifecycleUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sessionDir: URL!
    private var fixturesDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()

        fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        try? "# File A".write(to: fixturesDir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try? "# File B".write(to: fixturesDir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try? "# File C".write(to: fixturesDir.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)

        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fileAPath = fixturesDir.appendingPathComponent("a.md").path
        let fileBPath = fixturesDir.appendingPathComponent("b.md").path
        let fileCPath = fixturesDir.appendingPathComponent("c.md").path

        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
            "-openFiles", "\(fileAPath),\(fileBPath),\(fileCPath)",
        ]
    }

    override func tearDown() async throws {
        captureSessionCheckpoint("Journey state before teardown")
        app.terminate()
        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: fixturesDir)
    }

    func testOpenFilesDirtyClosePromptAndRestore() {
        app.launch()
        app.activate()

        // Wait for the document window and native tab bar tabs.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let tabA = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "a.md")).firstMatch
        let tabB = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "b.md")).firstMatch
        let tabC = app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", "c.md")).firstMatch
        XCTAssertTrue(tabA.waitForExistence(timeout: 5))
        XCTAssertTrue(tabB.exists)
        XCTAssertTrue(tabC.exists)

        // Activate b.md and dirty it using the debug menu. Use the app's own
        // "Select Tab 2" command so the native tab switch also makes b.md's
        // window key; a raw accessibility click on the tab bar does not reliably
        // update the key window under UI automation.
        app.menuBars.menuBarItems["Window"].click()
        app.menuBars.menuBarItems["Window"].menuItems["Select Tab 2"].firstMatch.click()

        // Wait for the tab switch to complete so the next command targets the
        // correct window. The native tab bar exposes selection as `value == 1`
        // on macOS 26; if this assertion flakes on a future macOS version,
        // switch to an `isSelected == YES` predicate if AppKit exposes it.
        let selectedB = app.tabs.matching(NSPredicate(
            format: "value == %d AND title CONTAINS[c] %@", 1, "b.md"
        )).firstMatch
        XCTAssertTrue(selectedB.waitForExistence(timeout: 5))

        app.menuBars.menuBarItems["Debug"].click()
        app.menuBars.menuBarItems["Debug"].menuItems["Mark Active Tab Dirty"].click()

        // Close the active tab via the File menu.
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuBarItems["File"].menuItems["Close Tab"].click()

        // Verify the dirty-close alert appears.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.buttons["Discard Changes"].exists)

        // Cancel the close.
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(tabB.waitForExistence(timeout: 5))

        // Terminate the app. NSRunningApplication.terminate() delivers a 'quit'
        // Apple event that routes through applicationShouldTerminate, which saves
        // the session before exiting. Using terminate() avoids a menu-dismissal
        // focus switch that can reorder native tabs under UI automation.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        // Wait for the session file to be written after termination.
        let sessionFile = sessionDir.appendingPathComponent("session.json")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: sessionFile.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path), "Session file was not written")

        captureSessionCheckpoint("Saved session after normal termination")

        // Relaunch with the same session directory but without -openFiles so
        // the app restores from the saved session.
        app.launchArguments = [
            "-UITesting",
            "-sessionDir", sessionDir.path,
        ]
        app.launch()
        app.activate()

        // Verify all three tabs restored and b.md is selected again.
        // Re-query the tabs after relaunch to avoid stale accessibility references.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(tab(named: "a.md").waitForExistence(timeout: 5))
        XCTAssertTrue(tab(named: "b.md").exists)
        XCTAssertTrue(tab(named: "c.md").exists)

        let selectedTab = app.tabs.matching(NSPredicate(
            format: "value == %d AND title CONTAINS[c] %@", 1, "b.md"
        )).firstMatch
        XCTAssertTrue(
            selectedTab.waitForExistence(timeout: 5),
            "Expected b.md to be the restored active tab"
        )
    }

    func testQuickOpenReactivatesAnAlreadyOpenBackgroundTab() {
        app.launchArguments += ["-openFolder", fixturesDir.path]
        app.launch()
        app.activate()

        let launchDeadline = Date().addingTimeInterval(8)
        let tabA = tab(named: "a.md")
        XCTAssertTrue(tabA.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForInitialTabBatch(until: launchDeadline))
        XCTAssertTrue(tab(named: "b.md").exists)
        XCTAssertTrue(tab(named: "c.md").exists)

        app.menuBars.menuBarItems["Window"].click()
        app.menuBars.menuBarItems["Window"].menuItems["Select Tab 2"].firstMatch.click()
        let selectedB = app.tabs.matching(NSPredicate(
            format: "value == %d AND title CONTAINS[c] %@", 1, "b.md"
        )).firstMatch
        XCTAssertTrue(selectedB.waitForExistence(timeout: 5))

        // Folder roots belong to each document window. The launch root was
        // applied to the last-opened window; explicitly choose it on b.md too.
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuBarItems["File"].menuItems["Open Folder…"].click()
        let origins = app.windows.matching(NSPredicate(format: "title CONTAINS[c] %@", "b.md"))
        XCTAssertEqual(origins.count, 1, "Folder selection belongs to the unique selected document window")
        let origin = origins.firstMatch
        XCTAssertTrue(origin.exists)
        let panel = origin.sheets.matching(identifier: "open-panel").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        requireCompactChooserView(panel)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(fixturesDir.path)
        app.typeKey(.return, modifierFlags: [])
        let open = panel.buttons["Open Folder"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND hittable == YES"), object: open
        )
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed)
        open.click()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "fileRow-a.md").firstMatch.waitForExistence(timeout: 5))

        app.typeKey("p", modifierFlags: .command)
        let search = app.textFields["quickOpenSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("a.md")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "quickOpenRow.a.md").firstMatch.waitForExistence(timeout: 8))
        app.typeKey(.return, modifierFlags: [])

        let selectedA = app.tabs.matching(NSPredicate(
            format: "value == %d AND title CONTAINS[c] %@", 1, "a.md"
        )).firstMatch
        XCTAssertTrue(selectedA.waitForExistence(timeout: 8))
        XCTAssertEqual(app.tabs.count, 3, "Opening an existing file must reuse its native tab")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("# File A") == true)
    }

    private func waitForInitialTabBatch(until deadline: Date) -> Bool {
        if app.tabs.count == 3 {
            return true
        }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: app.tabs)
        return XCTWaiter().wait(for: [ready], timeout: remaining) == .completed
    }

    private func captureSessionCheckpoint(_ label: String) {
        if app.state != .notRunning {
            captureRemainingChoosers(label)
            let hierarchy = XCTAttachment(string: String(app.debugDescription.prefix(65536)))
            hierarchy.name = label + " accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        let session = sessionDir.appendingPathComponent("session.json")
        guard let handle = try? FileHandle(forReadingFrom: session) else { return }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 1_048_577) else { return }
        let attachment = if bytes.count <= 1_048_576 {
            XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        } else {
            XCTAttachment(string: "Generated session exceeds the diagnostic capture limit")
        }
        attachment.name = label + " generated session"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func requireCompactChooserView(_ panel: XCUIElement) {
        // Keep the chooser's automation surface to its current directory,
        // rather than column-mode ancestor listings of Library/Containers.
        app.typeKey("2", modifierFlags: .command)
        let listReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 2"), object: panel.outlines
        )
        XCTAssertEqual(XCTWaiter().wait(for: [listReady], timeout: 5), .completed)
        XCTAssertFalse(panel.browsers["ColumnView"].exists)
    }

    private func captureRemainingChoosers(_ label: String) {
        let panels = app.sheets.matching(identifier: "open-panel")
        var rows: [[String: Any]] = []
        for panel in panels.allElementsBoundByIndex.prefix(2) {
            let buttons: [[String: Any]] = panel.buttons.allElementsBoundByIndex.prefix(32).map { button in
                [
                    "identifier": String(button.identifier.prefix(256)), "label": String(button.label.prefix(256)),
                    "exists": button.exists, "enabled": button.isEnabled, "hittable": button.isHittable,
                    "frame": String(describing: button.frame),
                ]
            }
            rows.append([
                "identifier": panel.identifier, "frame": String(describing: panel.frame),
                "outlines": panel.outlines.count,
                "columnViews": panel.browsers.matching(identifier: "ColumnView").count,
                "buttons": buttons,
            ])
        }
        guard !rows.isEmpty, let bytes = try? JSONSerialization.data(withJSONObject: rows, options: .sortedKeys)
        else { return }
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        attachment.name = label + " remaining native chooser attributes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tab(named name: String) -> XCUIElement {
        app.tabs.matching(NSPredicate(format: "title CONTAINS[c] %@", name)).firstMatch
    }
}
