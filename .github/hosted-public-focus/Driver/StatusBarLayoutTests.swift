import Foundation
import XCTest

@MainActor
extension PublicFocusTests {
    @objc func testNormalStatusBarRemainsReadableAtNarrowAndWideWidths() throws {
        // Preserve the complete existing normal public journey and its assertions.
        try testNormalPublicFocusBoldAndUndo()
        let app = XCUIApplication(bundleIdentifier: "app.mostlytext.MostlyText")
        let window = app.windows.matching(NSPredicate(format: "title CONTAINS %@", HostedFocusInputs.fileName)).firstMatch
        let status = window.descendants(matching: .any).matching(identifier: "editorStatusBar").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let narrow = try recordStatusFrames(app, status: status, label: "Narrow status layout")
        let narrowWidth = status.frame.width
        XCTAssertGreaterThanOrEqual(narrowWidth, 300)
        XCTAssertLessThanOrEqual(narrowWidth, 480)

        app.typeKey("1", modifierFlags: [.command, .option])
        XCTAssertTrue(waitForStatusWidth(status) { $0 > narrowWidth + 100 })
        let wide = try recordStatusFrames(app, status: status, label: "Wide status layout")
        app.typeKey("2", modifierFlags: [.command, .option])
        XCTAssertTrue(waitForStatusWidth(status) { abs($0 - narrowWidth) < 20 })
        XCTAssertEqual(window.textViews.firstMatch.value as? String, "- item")

        XCTAssertLessThanOrEqual(narrow["editorStatusBar.height"] ?? .infinity, 52,
                                 "Status bar must fit at most two readable rows at a narrow editor width")
        XCTAssertLessThanOrEqual(wide["editorStatusBar.height"] ?? .infinity, 32)
        for identifier in statusItemIDs {
            XCTAssertGreaterThan(narrow[identifier + ".width"] ?? 0, 0)
            XCTAssertGreaterThan(wide[identifier + ".width"] ?? 0, 0)
            XCTAssertGreaterThanOrEqual(narrow[identifier + ".width"] ?? 0,
                                        (wide[identifier + ".width"] ?? .infinity) - 1,
                                        "Narrow layout must retain each item's fully readable wide-layout width")
            XCTAssertLessThanOrEqual(narrow[identifier + ".height"] ?? .infinity, 24,
                                     "Whole status items must not fragment into vertical words")
            XCTAssertLessThanOrEqual(wide[identifier + ".height"] ?? .infinity, 24)
        }
    }

    private var statusItemIDs: [String] {
        ["statusBarLineColumn", "statusBarCount", "statusBarSyntaxMode", "statusBarEncoding",
         "statusBarLineEnding", "statusBarIndentation"]
    }

    private func waitForStatusWidth(_ status: XCUIElement, condition: (CGFloat) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition(status.frame.width) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition(status.frame.width)
    }

    private func recordStatusFrames(_ app: XCUIApplication, status: XCUIElement, label: String) throws -> [String: CGFloat] {
        var frames = ["editorStatusBar.width": status.frame.width, "editorStatusBar.height": status.frame.height]
        for identifier in statusItemIDs {
            let item = status.descendants(matching: .any).matching(identifier: identifier).firstMatch
            frames[identifier + ".width"] = item.frame.width
            frames[identifier + ".height"] = item.frame.height
        }
        let data = try JSONSerialization.data(withJSONObject: frames.mapValues { Double($0) }, options: [.sortedKeys])
        let geometry = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        geometry.name = label + " actual frames"
        geometry.lifetime = .keepAlways
        add(geometry)
        let tree = XCTAttachment(string: String(app.debugDescription.prefix(131_072)))
        tree.name = label + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = label + " screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        return frames
    }
}
