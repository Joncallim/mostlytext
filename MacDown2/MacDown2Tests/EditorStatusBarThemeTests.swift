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
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let observed = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 3, y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.deviceRGB))
            let expected = try #require(ResolvedPresentationPalette(theme: theme).statusBackground.nsColor
                .usingColorSpace(.deviceRGB))
            print("Status theme=\(theme.id) observed=\(observed) expected=\(expected)")
            #expect(abs(observed.redComponent - expected.redComponent) < 0.03)
            #expect(abs(observed.greenComponent - expected.greenComponent) < 0.03)
            #expect(abs(observed.blueComponent - expected.blueComponent) < 0.03)
            #expect(host.rootView.source as String == source)
        }
    }
}
