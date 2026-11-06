import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct EditorCurrentLineSemanticsTests {
    @Test func thePrimarySelectionOwnsTheLineAcrossUnicodeAndMixedEndings() {
        let source = "😀 first\r\nsecond\rthird\nlast\n"
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: source, configuration: .default)
        let third = (source as NSString).range(of: "third").location
        system.selectionSet = .init(
            ranges: [.init(location: 0, length: 0), .init(location: third, length: 0)],
            primaryIndex: 1
        )
        #expect(system.currentLogicalLine == 3)
        system.selectionSet = .init(single: .init(location: source.utf16.count, length: 0))
        #expect(system.currentLogicalLine == 5)
        #expect(system.textView.string.utf8.elementsEqual(source.utf8))
    }

    @Test func anEmptyEditorHasOneCurrentLineAndNoDecorationEdits() {
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: "", configuration: .default)
        #expect(system.currentLogicalLine == 1)
        let undo = system.undoManager.canUndo
        (system.textView as? EditorTextView)?.currentLineColor = .red
        #expect(system.text == "" && system.selectedRange == .init(location: 0, length: 0))
        #expect(system.undoManager.canUndo == undo)
    }

    @Test(arguments: ["", "first\n", String(repeating: "wrapped words ", count: 50)])
    func emptyTrailingAndWrappedLinesKeepTheirActualBackground(_ source: String) throws {
        var configuration = EditorConfiguration.default
        configuration.scrollsPastEnd = false
        configuration.textInsets = .init(width: 8, height: 20)
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: source, configuration: configuration)
        let view = try #require(system.textView as? EditorTextView)
        let bounds = NSRect(x: 0, y: 0, width: 240, height: 600)
        let scroll = NSScrollView(frame: bounds)
        scroll.documentView = view
        system.scrollView = scroll
        view.frame = bounds
        let window = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        system.selectionSet = .init(single: .init(location: source.utf16.count, length: 0))
        view.currentLineColor = .red
        // These tiny fixtures materialize only their current viewport, through
        // the same real draw call that must paint the production background.
        let image = NSImage(size: bounds.size, flipped: true) { _ in view.draw(view.visibleRect); return true }
        var proposed = bounds
        let bitmap = try NSBitmapImageRep(cgImage: #require(image.cgImage(
            forProposedRect: &proposed,
            context: nil,
            hints: nil
        )))
        var coloredRows = 0
        for row in 0 ..< bitmap.pixelsHigh {
            if let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: row)?.usingColorSpace(.deviceRGB),
               color.redComponent - max(color.greenComponent, color.blueComponent) > 0.3 {
                coloredRows += 1
            }
        }
        var geometry: [String] = []
        system.layoutManager.enumerateTextLayoutFragments(from: nil, options: []) { fragment in
            geometry
                .append(
                    "frame=\(fragment.layoutFragmentFrame), rows=\(fragment.textLineFragments.map(\.characterRange))"
                )
            return geometry.count < 100
        }
        print("Current-line empty/wrapped bytes=\(source.utf8.count) redRows=\(coloredRows) \(geometry)")
        #expect(coloredRows > 0, "Every current logical line, including empty/EOF, must have a real theme background")
        if source.utf8.count > 100 {
            #expect(
                coloredRows > 2 * Int(view.font?.pointSize ?? 13),
                "A wrapped logical line includes every visible row"
            )
        }
        #expect(system.textView.string.utf8.elementsEqual(source.utf8))
    }

    @Test func currentLineDrawingKeepsTenMiBViewportWorkBounded() throws {
        let source = String(repeating: "line content\n", count: 810_000)
        var configuration = EditorConfiguration.default
        configuration.scrollsPastEnd = false
        configuration.textInsets = .init(width: 8, height: 30)
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: source, configuration: configuration)
        let view = try #require(system.textView as? EditorTextView)
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 700)
        let scroll = NSScrollView(frame: bounds)
        scroll.documentView = view
        system.scrollView = scroll
        view.frame = .init(x: 0, y: 0, width: 800, height: 20000)
        let window = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        scroll.contentView.scroll(to: .init(x: 0, y: 250))
        scroll.reflectScrolledClipView(scroll.contentView)
        var offsets: [Int] = []
        system.enumerateVisibleLineFragments { offset, _ in offsets.append(offset) }
        let offset = try #require(offsets.dropFirst(2).first)
        system.selectionSet = .init(single: .init(location: offset, length: 0))
        view.currentLineColor = .red
        var visits = 0
        let start = ContinuousClock.now
        let image = NSImage(size: view.visibleRect.size, flipped: true) { _ in
            NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: -view.visibleRect.minY)
            visits = view.drawCurrentLineBackground(in: view.visibleRect)
            return true
        }
        var proposed = NSRect(origin: .zero, size: image.size)
        _ = try #require(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        let elapsed = start.duration(to: .now)
        print("CURRENT-LINE-PHASE source_bytes=\(source.utf8.count) visited=\(visits) duration=\(elapsed)")
        #expect(source.utf8.count > 10 * 1024 * 1024)
        #expect(visits > 0 && visits < 500)
        #expect(system.textView.visibleRect.minY > 0)
        #expect(system.selectionSet.primaryRange.location == offset)
    }
}
