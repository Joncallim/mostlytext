import AppKit
import EditorCore
@testable import MacDown2
import SwiftUI
import Testing
import Themes

@MainActor
@Suite(.serialized)
struct EditorStatusBarThemeTests {
    @Test func liveStatusPalettePaintsEveryBundledThemeWithoutEditingSource() throws {
        let source = "unchanged source 😀\n"
        let metrics = EditorDocumentMetrics(of: source)
        let lineIndex = EditorLineIndex(text: source as NSString)
        func bar(_ theme: Theme) -> EditorStatusBarView {
            EditorStatusBarView(source: source as NSString, metrics: metrics,
                                selectedRange: .init(location: 0, length: 0), lineIndex: lineIndex,
                                indentationWidth: 4, convertsTabsToSpaces: true, onGoToLine: {},
                                palette: .init(theme: theme))
        }
        let frame = NSRect(x: 0, y: 0, width: 700, height: 30)
        let host = NSHostingView(rootView: bar(BundledThemes.light))
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        for theme in BundledThemes.all {
            host.rootView = bar(theme)
            host.layoutSubtreeIfNeeded()
            host.display()
            let bitmap = try captureSRGB(host)
            let observed = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 3, y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.sRGB))
            let expected = try #require(ResolvedPresentationPalette(theme: theme).statusBackground.nsColor
                .usingColorSpace(.sRGB))
            let reference = try referenceColor(expected, in: bitmap)
            print("Status theme=\(theme.id) space=\(bitmap.colorSpace) observed=\(observed) "
                + "reference=\(reference) expected=\(expected)")
            #expect(abs(reference.redComponent - expected.redComponent) < 0.01)
            #expect(abs(reference.greenComponent - expected.greenComponent) < 0.01)
            #expect(abs(reference.blueComponent - expected.blueComponent) < 0.01)
            #expect(abs(observed.redComponent - expected.redComponent) < 0.03)
            #expect(abs(observed.greenComponent - expected.greenComponent) < 0.03)
            #expect(abs(observed.blueComponent - expected.blueComponent) < 0.03)
            #expect(host.rootView.source as String == source)
        }
    }

    private func captureSRGB(_ host: NSHostingView<EditorStatusBarView>) throws -> NSBitmapImageRep {
        let width = max(1, Int(host.bounds.width.rounded(.up)))
        let height = max(1, Int(host.bounds.height.rounded(.up)))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitmap = try NSBitmapImageRep(cgImage: #require(context.makeImage()))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func referenceColor(_ color: NSColor, in bitmap: NSBitmapImageRep) throws -> NSColor {
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext)
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: bitmap.pixelsHigh))
        return try #require(bitmap.colorAt(x: 3, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }
}
