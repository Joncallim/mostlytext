import AppKit
import CoreGraphics
import CoreText
import Foundation
@testable import MacDown2
import PDFKit
import Testing

/// Paper geometry and text preservation for multi-page WebKit vector output.
@MainActor
struct PDFMultiPageFallbackTests {
    @Test func severalOversizedVectorPagesBecomePaperPages() throws {
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
        let output = try PDFSnapshotFallback.paginate(data as Data, printInfo: info, maxBytes: 1_000_000)
        let result = try #require(PDFDocument(data: output))
        #expect(result.pageCount == 6)
        #expect((0 ..< result.pageCount).allSatisfy {
            result.page(at: $0)?.bounds(for: .mediaBox).size == info.paperSize
        })
        #expect(result.page(at: 0)?.string?.contains("FIRST") == true)
        #expect(result.page(at: 5)?.string?.contains("LAST") == true)
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
