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
            let observed = try rawRGB(in: bitmap, x: bitmap.pixelsWide - 3, y: bitmap.pixelsHigh / 2)
            let expected = ResolvedPresentationPalette(theme: theme).statusBackground
            let reference = try referenceColor(expected)
            print("Status theme=\(theme.id) space=\(bitmap.colorSpace) observed=\(observed) "
                + "reference=\(reference) expected=\(expected)")
            #expect(abs(reference.red - expected.red) < 0.01)
            #expect(abs(reference.green - expected.green) < 0.01)
            #expect(abs(reference.blue - expected.blue) < 0.01)
            #expect(abs(observed.red - expected.red) < 0.03)
            #expect(abs(observed.green - expected.green) < 0.03)
            #expect(abs(observed.blue - expected.blue) < 0.03)
            #expect(host.rootView.source as String == source)
        }
    }

    private func captureSRGB(_ host: NSHostingView<EditorStatusBarView>) throws -> NSBitmapImageRep {
        let width = max(1, Int(host.bounds.width.rounded(.up)))
        let height = max(1, Int(host.bounds.height.rounded(.up)))
        let context = try makeContext(width: width, height: height)
        let bitmap = try NSBitmapImageRep(cgImage: #require(context.makeImage()))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func referenceColor(_ color: ThemeColor) throws -> RGB {
        let context = try makeContext(width: 1, height: 1)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let fill = try #require(CGColor(colorSpace: space, components:
            [color.red, color.green, color.blue, color.alpha].map { CGFloat($0) }))
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.flush()
        let bitmap = try NSBitmapImageRep(cgImage: #require(context.makeImage()))
        return try rawRGB(in: bitmap, x: 0, y: 0)
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func rawRGB(in bitmap: NSBitmapImageRep, x pixelX: Int, y pixelY: Int) throws -> RGB {
        try #require(bitmap.bitsPerSample == 8 && bitmap.samplesPerPixel == 4 && !bitmap.isPlanar)
        var samples = [UInt](repeating: 0, count: 4)
        bitmap.getPixel(&samples, atX: pixelX, y: pixelY)
        let first = bitmap.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        try #require(samples[first == 0 ? 3 : 0] == 255, "The sampled background must be opaque")
        return RGB(red: Double(samples[first]) / 255,
                   green: Double(samples[first + 1]) / 255, blue: Double(samples[first + 2]) / 255)
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }
}
