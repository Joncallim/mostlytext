import Foundation
import XCTest

/// Captures the actual app's Markdown Preview geometry for the exponent
/// variants reported by the disposable test account. This diagnostic does
/// not substitute a reconstructed fixture for that account's original bytes.
@MainActor
final class MathExponentVisualUITests: XCTestCase {
    func testFullAppExponentImagesAreInspectable() throws {
        let source = """
        # Math variants

        Control: $E$ $m$ $mc$ $E=mc$ $x+1$

        Inline: $E=mc^2$ and $x^2$ and $x^{2}$.

        Display:

        $$ E=mc^2 $$

        """
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-math-ui-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("session", isDirectory: true)
        let fixture = root.appendingPathComponent("math-variants.md")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try source.write(to: fixture, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-sessionDir", session.path, "-openFiles", fixture.path]
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: root)
        }
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let preview = app.descendants(matching: .any).matching(identifier: "previewPane").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Actual document Preview was not published")

        for expression in ["E=mc^2", "x^2", "x^{2}"] {
            captureImage(app, predicate: NSPredicate(format: "label == %@", "Inline equation: \(expression)"),
                         name: "inline \(expression)")
        }
        captureImage(app, predicate: NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                 "Display equation:", "E=mc^2"), name: "display E=mc^2")
        attachWindowScreenshot(app, named: "MostlyText math variants")
    }

    private func captureImage(_ app: XCUIApplication, predicate: NSPredicate, name: String) {
        let image = app.images.matching(predicate).firstMatch
        guard image.waitForExistence(timeout: 20) else {
            attachWindowScreenshot(app, named: "Missing \(name) in MostlyText window")
            XCTFail("Missing native image for \(name)")
            return
        }
        XCTAssertGreaterThan(image.frame.width, 0, "Equation has no rendered frame: \(name)")
        let attachment = XCTAttachment(screenshot: image.screenshot())
        attachment.name = "Rendered \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachWindowScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
