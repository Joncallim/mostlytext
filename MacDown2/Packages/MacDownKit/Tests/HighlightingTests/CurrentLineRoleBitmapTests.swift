import AppKit
@testable import EditorCore
import Foundation
import Highlighting
import Testing
import Themes

/// Uses only APIs present on the original main baseline. The exact same file
/// must fail there and pass after activating the real theme/drawing path.
@MainActor
@Suite(.serialized)
struct CurrentLineRoleBitmapTests {
    @Test func anAppliedThemePaintsAndRemovesTheCurrentLineInTheRealScrolledEditor() throws {
        var configuration = EditorConfiguration.default
        configuration.textInsets = .init(width: 4, height: 30)
        configuration.scrollsPastEnd = false
        let source = (1 ... 100).map { "line \($0)" }.joined(separator: "\n")
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: source, configuration: configuration)
        let mounted = mount(system, height: 400, contentHeight: 3000)
        defer { dispose(mounted.window) }
        var theme = BundledThemes.light
        theme.chrome.background = .init(red: 1, green: 1, blue: 1, alpha: 1)
        theme.chrome.foreground = .init(red: 0, green: 0, blue: 0, alpha: 1)
        theme.chrome.caret = theme.chrome.foreground
        theme.chrome.currentLine = .init(red: 1, green: 0, blue: 0, alpha: 1)
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: nil, theme: theme, registry: GrammarRegistry()
        )
        defer { highlighter.tearDown() }
        mounted.scroll.contentView.scroll(to: .init(x: 0, y: 250))
        mounted.scroll.reflectScrolledClipView(mounted.scroll.contentView)
        var offsets: [Int] = []
        system.enumerateVisibleLineFragments { offset, _ in offsets.append(offset) }
        let target = try #require(offsets.dropFirst(2).first, "The actual scrolled viewport must contain several lines")
        system.selectionSet = .init(single: .init(location: target, length: 0))
        let selection = system.selectionSet
        let undo = system.textView.undoManager?.canUndo
        try #require(system.textView.visibleRect.minY > 0)
        let colored = try render(system.textView, dirty: system.textView.visibleRect)
        theme.chrome.currentLine = .init(red: 0, green: 0, blue: 0, alpha: 0)
        highlighter.applyTheme(theme)
        let cleared = try render(system.textView, dirty: system.textView.visibleRect)
        #expect(redPixels(colored) > 0, "The production theme application and draw path must paint the current row")
        #expect(redPixels(cleared) == 0, "A live theme change must remove the old current-line color")
        #expect(system.textView.string.utf8.elementsEqual(source.utf8))
        #expect(system.selectionSet == selection && system.textView.undoManager?.canUndo == undo)
    }

    @Test func aShapeIdentifiesThePrimaryLineEvenWhenTheEditorFontIsAlreadyBold() throws {
        let system = EditorTextSystem(
            identity: UUID().uuidString,
            initialText: "first\nsecond",
            configuration: .default
        )
        system.textView.font = .boldSystemFont(ofSize: 14)
        system.textView.backgroundColor = .white
        system.textView.textColor = .black
        let mounted = mount(system, height: 120, contentHeight: 120)
        defer { dispose(mounted.window) }
        let gutter = EditorGutterView(scrollView: mounted.scroll, system: system)
        mounted.scroll.verticalRulerView = gutter
        mounted.scroll.hasVerticalRuler = true
        mounted.scroll.rulersVisible = true
        var baselines: [CGFloat] = []
        system.enumerateVisibleLineFragments { _, baseline in baselines.append(baseline) }
        let baseline = try #require(baselines.dropFirst().first)
        let viewBaseline = gutter.convert(
            .init(x: 0, y: baseline + system.textView.textContainerInset.height), from: system.textView
        ).y
        let font = try #require(system.textView.font)
        system.selectionSet = .init(single: .init(location: 0, length: 0))
        let inactive = try renderGutter(gutter)
        system.selectionSet = .init(single: .init(location: 6, length: 0))
        let active = try renderGutter(gutter)
        let scaleX = CGFloat(active.pixelsWide) / gutter.bounds.width
        let scaleY = CGFloat(active.pixelsHigh) / gutter.bounds.height
        let columns = 0 ..< Int((gutter.bounds.width - 16) * scaleX)
        let rows = Int((viewBaseline - font.ascender) * scaleY) ..< Int((viewBaseline + 1) * scaleY)
        #expect(ink(active, columns: columns, rows: rows) > 0, "The current row needs a shape cue beyond font weight")
        #expect(ink(inactive, columns: columns, rows: rows) == 0)
        #expect(system.textView.string == "first\nsecond")
    }

    private func mount(_ system: EditorTextSystem, height: CGFloat, contentHeight: CGFloat)
        -> (window: NSWindow, scroll: NSScrollView) {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 300, height: height)
        let scroll = NSScrollView(frame: frame)
        scroll.documentView = system.textView
        system.scrollView = scroll
        system.textView.frame = .init(x: 0, y: 0, width: 300, height: contentHeight)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        return (window, scroll)
    }

    private func dispose(_ window: NSWindow) {
        window.orderOut(nil)
        window.close()
    }

    private func render(_ view: NSTextView, dirty: NSRect) throws -> NSBitmapImageRep {
        let image = NSImage(size: view.bounds.size, flipped: true) { _ in
            view.draw(dirty)
            return true
        }
        return try bitmap(image)
    }

    private func renderGutter(_ gutter: EditorGutterView) throws -> NSBitmapImageRep {
        let image = NSImage(size: gutter.bounds.size, flipped: true) { _ in
            gutter.drawHashMarksAndLabels(in: gutter.bounds)
            return true
        }
        return try bitmap(image)
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        var proposed = NSRect(origin: .zero, size: image.size)
        return try NSBitmapImageRep(cgImage: #require(image.cgImage(
            forProposedRect: &proposed,
            context: nil,
            hints: nil
        )))
    }

    private func redPixels(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for pixelY in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for pixelX in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB),
                   color.redComponent - max(color.greenComponent, color.blueComponent) > 0.3 {
                    count += 1
                }
            }
        }
        return count
    }

    private func ink(_ bitmap: NSBitmapImageRep, columns: Range<Int>, rows: Range<Int>) -> Int {
        var count = 0
        for pixelY in rows where pixelY >= 0 && pixelY < bitmap.pixelsHigh {
            for pixelX in columns where pixelX >= 0 && pixelX < bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB),
                   color.redComponent < 0.5 {
                    count += 1
                }
            }
        }
        return count
    }
}
