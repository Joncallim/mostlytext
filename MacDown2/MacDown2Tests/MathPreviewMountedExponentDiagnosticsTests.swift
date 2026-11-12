import AppKit
import ApplicationServices
import Foundation
@testable import MacDown2
import Math
import Testing
@testable import Textual

/// Uses the real document/window/split-view path implicated by the UID-502 report.
/// The source is disposable and contains only the reported simple exponent cases.
@MainActor
struct MathMountedExponentDiagnosticsTests {
    @Test func productionPreviewPublishesExponentImagesAndCapturesItsPaintedFrame() async throws {
        let source = """
        # Exponent frame

        Plain $E$, $m$, $mc$, $E=mc$ and $x+1$.

        Inline exponents $E=mc^2$, $x^2$ and $x^{2}$.

        $$
        E=mc^2
        $$

        Escaped \\$5 before $x+1$. Prices $12 and $15 remain prose.
        """
        let fixture = try PreviewProductionFixture(source: source)
        defer { fixture.dispose() }
        let window = try #require(fixture.first.window)
        window.setContentSize(.init(width: 900, height: 600))
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        try await requireOwnAccessibilityRole()
        let root = try fixture.root()
        let inline = MathDiagnosticText.equationLabel("x^2", isDisplay: false)
        try await fixture.wait("mounted inline exponent accessibility image", until: {
            let mounted = labels(in: root)
            return mounted.contains(inline)
                && mounted.contains(MathDiagnosticText.equationLabel("E=mc^2", isDisplay: false))
                && mounted.contains(MathDiagnosticText.equationLabel("x^{2}", isDisplay: false))
        })
        #expect(labels(in: root).contains { $0.hasPrefix("Display equation:") && $0.contains("E=mc^2") })
        let native = PreviewProductionFixture.descendants(root).compactMap { $0 as? Textual.NSTextInteractionView }
        #expect(!native.isEmpty)
        let layout = native.map { fixture.copyHarness.attachmentLayoutDiagnostics(in: $0) }
            .joined(separator: "\n--- next native view ---\n")
        #expect(layout.contains("actualAttachmentRuns="))
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOSTLYTEXT_EXPONENT_OUTPUT"]
            ?? NSTemporaryDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try layout.write(to: output.appendingPathComponent("mounted-exponents-layout.txt"),
                         atomically: true, encoding: .utf8)
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("mounted-exponents-frame.png"))
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        print("Mounted exponent frame: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh); \(output.path)")
    }

    private func requireOwnAccessibilityRole() async throws {
        let result = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let timeout = AXUIElementSetMessagingTimeout(process, 0.5)
            guard timeout == .success else { return (timeout.rawValue, String?.none) }
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(process, kAXRoleAttribute as CFString, &role)
            return (error.rawValue, role as? String)
        }.value
        try #require(result.0 == AXError.success.rawValue && result.1 == (kAXApplicationRole as String),
                     "The actual native accessibility client must be initialized")
    }

    private func labels(in root: NSView) -> Set<String> {
        var found = Set<String>()
        var seen = Set<ObjectIdentifier>()
        let selector = NSSelectorFromString("accessibilityLabel")
        let children = NSSelectorFromString("accessibilityChildren")
        func visit(_ object: NSObject, depth: Int) {
            guard depth <= 25, seen.count < 2048, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if object.responds(to: selector),
               let value = object.perform(selector)?.takeUnretainedValue() as? String {
                found.insert(value)
            }
            if object.responds(to: children),
               let nested = object.perform(children)?.takeUnretainedValue() as? [Any] {
                for case let child as NSObject in nested {
                    visit(child, depth: depth + 1)
                }
            }
            if let native = object as? NSView {
                for child in native.subviews {
                    visit(child, depth: depth + 1)
                }
            }
        }
        visit(root, depth: 0)
        return found
    }
}
