import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review of the combined tree: `coreTextMatrixKeepsAsymmetricGlyphsUprightInTheFlippedGutter` only exercised the
/// static helper with the test's own renderer, so deleting the `textMatrix` line from `drawHashMarksAndLabels` left
/// every gutter test green. This renders the PRODUCTION draw path into a flipped bitmap (the arrangement AppKit gives
/// a mounted ruler) and compares the second label ("2", an asymmetric glyph) with an upright and an inverted reference.
@MainActor
@Suite("EditorGutterView production draw path")
struct EditorGutterViewDrawPathTests {
    private struct Mask {
        var rows: [[Bool]]
        var height: Int {
            rows.count
        }

        var width: Int {
            rows.first?.count ?? 0
        }
    }

    private func makeBitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
    }

    private func luma(_ bitmap: NSBitmapImageRep, _ column: Int, _ row: Int) -> CGFloat {
        guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return 1 }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }

    /// The tight ink bounding box of the SECOND vertical cluster of ink (the "2" label under the "1" label).
    private func secondLabelMask(in bitmap: NSBitmapImageRep, background: CGFloat, columns: Range<Int>) -> Mask? {
        let inked: (Int, Int) -> Bool = { column, row in abs(luma(bitmap, column, row) - background) > 0.12 }
        let height = bitmap.pixelsHigh
        let rowHasInk = (0 ..< height).map { row in columns.contains { inked($0, row) } }
        var clusters: [ClosedRange<Int>] = []
        var start: Int?
        for (row, hasInk) in rowHasInk.enumerated() {
            if hasInk, start == nil {
                start = row
            }
            if !hasInk, let begin = start {
                clusters.append(begin ... row - 1)
                start = nil
            }
        }
        if let begin = start {
            clusters.append(begin ... height - 1)
        }
        guard clusters.count >= 2 else { return nil }
        let band = clusters[1]
        let inkColumns = columns.filter { column in band.contains { inked(column, $0) } }
        guard let first = inkColumns.first, let last = inkColumns.last else { return nil }
        return Mask(rows: band.map { row in (first ... last).map { inked($0, row) } })
    }

    /// Where the glyph's widest horizontal stroke sits, as a fraction of the glyph's height from the top (0 = top
    /// edge, 1 = bottom edge). The "2" is the one digit whose widest stroke is its flat base: about 1 when drawn
    /// upright and about 0 when vertically inverted. Rows that carry at least 80% of the widest row's ink count, so
    /// the answer does not depend on the installed font, the pixel size or anti-aliasing (a raw ink-count difference
    /// scored 1 instead of > 2 on the hosted runner, and a bottom-versus-top ink ratio was too close to zero).
    private func widestStrokePosition(_ mask: Mask) -> Double {
        let inkPerRow = mask.rows.map { row in row.filter(\.self).count }
        guard let widest = inkPerRow.max(), widest > 0, mask.height > 1 else { return 0.5 }
        let heavyRows = inkPerRow.indices.filter { Double(inkPerRow[$0]) >= 0.8 * Double(widest) }
        let centre = Double(heavyRows.reduce(0, +)) / Double(heavyRows.count)
        return centre / Double(mask.height - 1)
    }

    @Test func theProductionDrawPathRendersAnUprightSecondLineNumberInTheFlippedGutter() throws {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "one\ntwo")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        let gutter = EditorGutterView(scrollView: scrollView, system: system)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        #expect(gutter.isFlipped)
        // Keep the orientation specimen an ordinary numeral, as before active
        // line weight/shape existed. Those cues have separate bitmap controls.
        system.selectionSet = .init(single: .init(location: 0, length: 0))
        try #require(system.currentLogicalLine == 1)

        let bounds = gutter.bounds
        let height = max(1, Int(bounds.height))
        // Rendered at 4x so the glyph has enough pixels for the shape test to be meaningful on any font.
        let scale = 4
        let bitmap = try makeBitmap(width: max(1, Int(bounds.width)) * scale, height: height * scale)
        let cgContext = try #require(NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext)
        cgContext.translateBy(x: 0, y: CGFloat(height * scale))
        cgContext.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        let context = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        gutter.drawHashMarksAndLabels(in: bounds)

        let background = luma(bitmap, 0, 0)
        let font = system.textView.font ?? .systemFont(ofSize: 14)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let width = max(("2" as NSString).size(withAttributes: [.font: font]).width,
                        ("2" as NSString).size(withAttributes: [.font: bold]).width)
        // The new gutter shape is a separate cue with its own bitmap test.
        // Measure numeral orientation only in the right-aligned glyph columns.
        let firstColumn = max(0, Int(floor((bounds.width - 6 - width) * CGFloat(scale))) - 1)
        let columns = firstColumn ..< bitmap.pixelsWide
        print("Gutter orientation primary=\(system.currentLogicalLine) selection=\(system.selectedRange)")
        let produced = try #require(secondLabelMask(in: bitmap, background: background, columns: columns),
                                    "two numeral labels must be drawn")
        // Mutation-checked: without the production `textMatrix` line the base sits at about 0.19; with it, 0.81.
        let producedScore = widestStrokePosition(produced)
        #expect(
            producedScore > 0.6,
            "the production-drawn '2' must be upright, i.e. its flat base is at the bottom (\(producedScore))"
        )
    }
}
