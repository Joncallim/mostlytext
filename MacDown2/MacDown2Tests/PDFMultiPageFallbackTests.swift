import AppKit
import CoreGraphics
import CoreText
import Foundation
@testable import MacDown2
import Testing

/// Direct paper geometry and fail-closed oversized WebKit vector controls.
@MainActor
struct PDFMultiPageFallbackTests {
    @Test func vectorPageWithClippedTextIsRefused() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 300)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let fontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
        context.beginPDFPage(nil)
        for (label, baseline) in [("LOW", 1.0), ("HIGH", 294.0)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: label, attributes: [fontKey: font]
            ))
            context.textPosition = CGPoint(x: 10, y: baseline)
            CTLineDraw(line, context)
        }
        context.endPDFPage()
        context.closePDF()

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 100, height: 100)
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        do {
            _ = try PDFSnapshotFallback.paginate(data as Data, printInfo: info, maxBytes: 1_000_000)
            Issue.record("Clipped source text must not be published")
        } catch PDFSnapshotFallback.FallbackError.invalidGeometry {
            // The prior destination stays untouched when the adapter rejects this source.
        } catch {
            Issue.record("Unexpected clipping rejection: \(error)")
        }
    }

    @Test func severalOversizedVectorPagesAreRefused() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 300)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let fontKey = NSAttributedString.Key(rawValue: kCTFontAttributeName as String)
        for label in ["FIRST", "LAST"] {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: label, attributes: [fontKey: font]
            ))
            context.textPosition = CGPoint(x: 10, y: label == "FIRST" ? 260 : 60)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 100, height: 100)
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        do {
            _ = try PDFSnapshotFallback.paginate(data as Data, printInfo: info, maxBytes: 1_000_000)
            Issue.record("Oversized source pages must not be republished under paper clipping")
        } catch PDFSnapshotFallback.FallbackError.invalidGeometry {
            // Each original source page remains isolated in scratch.
        }
    }

    @Test func alreadyPaperSizedVectorPagesKeepTheirOriginalBytes() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0 ..< 2 {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 100, height: 100)
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        let original = data as Data
        #expect(try PDFSnapshotFallback.paginate(original, printInfo: info, maxBytes: 1_000_000) == original)
    }
}
