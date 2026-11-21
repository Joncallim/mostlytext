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
        assertStaticMath(in: finder)
        let staged = URL(fileURLWithPath: "/Users/runner/work/_temp/production-quicklook/installed/MostlyText.app")
        let source = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-production-quicklook.md")
        let handlers = NSWorkspace.shared.urlsForApplications(toOpen: source)
        XCTAssertTrue(handlers.contains(staged.standardizedFileURL),
                      "The staged public app must appear as a Markdown Open With handler")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
        assertRelatedDocuments(in: finder, beside: source)
    }

    private func assertRelatedDocuments(in finder: XCUIApplication, beside source: URL) {
        assertSelectedSymlink(in: finder, source: source)
        assertEncodedUnicodeSource(in: finder, beside: source)
        assertStaticGraphviz(in: finder, beside: source)
        assertStaticMermaid(in: finder, beside: source)
        assertTwoGraphvizFences(in: finder, beside: source)
        assertMixedGraphvizFailure(in: finder, beside: source)
        assertOversizedGraphvizFallback(in: finder, beside: source)
    }

    private func assertStaticMath(in finder: XCUIApplication) {
        let mathImage = finder.images["x^2"].firstMatch
        XCTAssertTrue(mathImage.waitForExistence(timeout: 5),
                      "The selected Markdown equation must become an accessible static image")
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

    private func assertStaticGraphviz(in finder: XCUIApplication, beside source: URL) {
        let diagram = source.deletingLastPathComponent()
            .appendingPathComponent("mostlytext-production-graphviz.md")
        NSWorkspace.shared.activateFileViewerSelecting([diagram])
        let item = finder.descendants(matching: .any)
            .matching(identifier: diagram.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the Graphviz fixture")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let heading = finder.staticTexts["MOSTLYTEXT_GRAPHVIZ_QUICKLOOK"].firstMatch
        let renderedNode = finder.staticTexts["ALPHA"].firstMatch
        let visible = heading.waitForExistence(timeout: 15)
            && renderedNode.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Graphviz Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Graphviz Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The actual sandboxed worker must render the Graphviz node")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }

    private func assertMixedGraphvizFailure(in finder: XCUIApplication, beside source: URL) {
        let mixed = source.deletingLastPathComponent()
            .appendingPathComponent("mostlytext-production-mixed-graphviz.md")
        NSWorkspace.shared.activateFileViewerSelecting([mixed])
        let item = finder.descendants(matching: .any)
            .matching(identifier: mixed.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the mixed fixture")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let heading = finder.staticTexts["MOSTLYTEXT_MIXED_GRAPHVIZ_QUICKLOOK"].firstMatch
        let math = finder.images["x^2"].firstMatch
        let goodNode = finder.staticTexts["GAMMA"].firstMatch
        let headingVisible = heading.waitForExistence(timeout: 15)
        let mathVisible = math.waitForExistence(timeout: 5)
        let goodNodeVisible = goodNode.waitForExistence(timeout: 5)
        let treeText = String(finder.debugDescription.prefix(65536))
        let tree = XCTAttachment(string: treeText)
        tree.name = "Mixed Graphviz Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Mixed Graphviz Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(headingVisible)
        XCTAssertTrue(mathVisible, "Static math must survive a malformed DOT fence")
        XCTAssertTrue(goodNodeVisible, "A valid DOT fence must survive the preceding malformed one")
        XCTAssertTrue(treeText.contains("value: digraph G {"), "Malformed DOT must remain readable source")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }

    private func assertTwoGraphvizFences(in finder: XCUIApplication, beside source: URL) {
        let diagrams = source.deletingLastPathComponent()
            .appendingPathComponent("mostlytext-production-two-graphviz.md")
        NSWorkspace.shared.activateFileViewerSelecting([diagrams])
        let item = finder.descendants(matching: .any)
            .matching(identifier: diagrams.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the two-graph fixture")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let heading = finder.staticTexts["MOSTLYTEXT_TWO_GRAPHVIZ_QUICKLOOK"].firstMatch
        let math = finder.images["x^2"].firstMatch
        let first = finder.staticTexts["FIRST"].firstMatch
        let third = finder.staticTexts["THIRD"].firstMatch
        let visible = heading.waitForExistence(timeout: 15)
            && math.waitForExistence(timeout: 5)
            && first.waitForExistence(timeout: 5)
            && third.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Two Graphviz fences Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Two Graphviz fences Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "Both completed Graphviz fences must be present in the latest snapshot")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }

    private func assertOversizedGraphvizFallback(in finder: XCUIApplication, beside source: URL) {
        let oversized = source.deletingLastPathComponent()
            .appendingPathComponent("mostlytext-production-oversized-graphviz.md")
        NSWorkspace.shared.activateFileViewerSelecting([oversized])
        let item = finder.descendants(matching: .any)
            .matching(identifier: oversized.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the oversized fixture")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let heading = finder.staticTexts["MOSTLYTEXT_OVERSIZED_GRAPHVIZ_QUICKLOOK"].firstMatch
        let headingVisible = heading.waitForExistence(timeout: 15)
        let treeText = String(finder.debugDescription.prefix(65536))
        let tree = XCTAttachment(string: treeText)
        tree.name = "Oversized Graphviz Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Oversized Graphviz Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(headingVisible)
        XCTAssertTrue(treeText.contains("value: digraph G {"), "Over-budget DOT must remain authored code")
        // WebKit truncates this very long code block in Finder's accessibility snapshot.
        // The rendered code opening and retained screenshot establish source fallback.
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }
}

private extension ProductionFinderTests {
    func assertStaticMermaid(in finder: XCUIApplication, beside source: URL) {
        let diagram = source.deletingLastPathComponent()
            .appendingPathComponent("mostlytext-production-mermaid.md")
        NSWorkspace.shared.activateFileViewerSelecting([diagram])
        let item = finder.descendants(matching: .any)
            .matching(identifier: diagram.lastPathComponent).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Finder must select the Mermaid fixture")
        item.click()
        finder.typeKey(.space, modifierFlags: [])
        let heading = finder.staticTexts["MOSTLYTEXT_MERMAID_QUICKLOOK"].firstMatch
        let renderedNode = finder.staticTexts["MERMAID_RENDERED_NODE"].firstMatch
        let visible = heading.waitForExistence(timeout: 15)
            && renderedNode.waitForExistence(timeout: 5)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Mermaid Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Mermaid Finder Quick Look window"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(visible, "The sandboxed worker must return static Mermaid SVG")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        finder.typeKey(.escape, modifierFlags: [])
    }
}
