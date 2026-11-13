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
        let gfmCell = finder.staticTexts["GFM_COLUMN_VALUE"].firstMatch
        let renderedGFM = gfmCell.waitForExistence(timeout: 5)
        let providerBrand = finder.staticTexts["MostlyText"].firstMatch
        let providerRendered = providerBrand.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Production Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Production Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The actual product extension must answer Finder with selected source")
        XCTAssertTrue(renderedGFM, "GFM table cells must be accessible as rendered structure")
        XCTAssertTrue(providerRendered, "Finder must show the provider-owned header, not a generic text preview")
        let staged = URL(fileURLWithPath: "/Users/runner/work/_temp/production-quicklook/installed/MostlyText.app")
        let source = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-production-quicklook.md")
        let handlers = NSWorkspace.shared.urlsForApplications(toOpen: source)
        XCTAssertTrue(handlers.contains(staged.standardizedFileURL),
                      "The staged public app must appear as a Markdown Open With handler")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
        assertSelectedSymlink(in: finder, source: source)
        assertEncodedUnicodeSource(in: finder, beside: source)
    }

    private func assertSelectedSymlink(in finder: XCUIApplication, source: URL) {
        let link = source.deletingLastPathComponent().appendingPathComponent("mostlytext-production-linked.md")
        NSWorkspace.shared.activateFileViewerSelecting([link])
        let item = finder.descendants(matching: .any).matching(identifier: link.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the linked Markdown file")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let marker = finder.staticTexts["MOSTLYTEXT_PRODUCTION_QUICKLOOK_20261111"].firstMatch
        let visible = marker.waitForExistence(timeout: 15)
        let gfmCell = finder.staticTexts["GFM_COLUMN_VALUE"].firstMatch
        let renderedGFM = gfmCell.waitForExistence(timeout: 5)
        let providerBrand = finder.staticTexts["MostlyText"].firstMatch
        let providerRendered = providerBrand.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Linked Markdown Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Linked Markdown Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The selected linked Markdown file must receive a bounded source reply")
        XCTAssertTrue(renderedGFM, "The selected linked file must receive rendered GFM")
        XCTAssertTrue(providerRendered, "The linked file must use the provider-owned renderer")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }

    private func assertEncodedUnicodeSource(in finder: XCUIApplication, beside source: URL) {
        let encoded = source.deletingLastPathComponent()
            .appendingPathComponent("mostlytext-production-utf16-be.md")
        NSWorkspace.shared.activateFileViewerSelecting([encoded])
        let item = finder.descendants(matching: .any).matching(identifier: encoded.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the UTF-16 BE Markdown file")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let heading = finder.staticTexts["QUICKLOOK_UTF16_BE_MARKER"].firstMatch
        let unicode = finder.staticTexts["日本語 😀"].firstMatch
        let visible = heading.waitForExistence(timeout: 15) && unicode.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "UTF-16 BE Markdown Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "UTF-16 BE Markdown Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The installed provider must decode BOM and CRLF without losing Unicode text")
        XCTAssertTrue(finder.staticTexts["MostlyText"].firstMatch.exists)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }
}
