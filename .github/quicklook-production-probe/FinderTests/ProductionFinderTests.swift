import AppKit
import Darwin
import XCTest

@MainActor
final class ProductionFinderTests: XCTestCase {
    func testInstalledProductionProviderShowsSelectedMarkdownSource() throws {
        continueAfterFailure = false
        XCTAssertEqual(getuid(), geteuid())
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.windows.firstMatch.waitForExistence(timeout: 10))
        let fileName = "mostlytext-production-quicklook.md"
        let file = finder.descendants(matching: .any).matching(identifier: fileName).firstMatch
        let named = finder.staticTexts[fileName].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists)
        if file.exists {
            file.click()
        } else {
            named.click()
        }
        finder.typeKey(.space, modifierFlags: [])

        let marker = finder.staticTexts["MOSTLYTEXT_PRODUCTION_QUICKLOOK_20261111"].firstMatch
        let visible = marker.waitForExistence(timeout: 15)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Production Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Production Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The actual product extension must answer Finder with selected source")
        let staged = URL(fileURLWithPath: "/Users/runner/work/_temp/production-quicklook/installed/MostlyText.app")
        let source = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-production-quicklook.md")
        let handlers = NSWorkspace.shared.urlsForApplications(toOpen: source)
        XCTAssertTrue(handlers.contains(staged.standardizedFileURL),
                      "The staged public app must appear as a Markdown Open With handler")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
        try assertSelectedSymlink(in: finder, source: source)
    }

    private func assertSelectedSymlink(in finder: XCUIApplication, source: URL) throws {
        let link = source.deletingLastPathComponent().appendingPathComponent("mostlytext-production-linked.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        defer { try? FileManager.default.removeItem(at: link) }
        NSWorkspace.shared.activateFileViewerSelecting([link])
        let item = finder.descendants(matching: .any).matching(identifier: link.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the linked Markdown file")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let marker = finder.staticTexts["MOSTLYTEXT_PRODUCTION_QUICKLOOK_20261111"].firstMatch
        let visible = marker.waitForExistence(timeout: 15)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Linked Markdown Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Linked Markdown Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The selected linked Markdown file must receive a bounded source reply")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }
}
