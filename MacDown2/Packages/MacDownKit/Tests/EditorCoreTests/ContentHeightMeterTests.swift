import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review pass 1: the whole-document `boundingRect` that sized the editor frame was quadratic
/// for non-Latin/mixed text — seconds to minutes on the main thread after every edit.
@MainActor
struct ContentHeightMeterTests {
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
    ]

    private func wholeStringHeight(_ text: String, width: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height
    }

    @Test(arguments: [
        "", "a", "a\n", "a\nb", "a\nb\n", "a\n\nb", "\n", "a\n\n", "a\r\nb\r\n", "a\rb",
        "日本語\n", "日本語\n\nx", "emoji 🎉 line\nnext",
        String(repeating: "word ", count: 200), String(repeating: "word ", count: 200) + "\nx",
        String(repeating: "日本語のテキスト ", count: 80) + "\nあ",
    ])
    func paragraphwiseHeightEqualsTheWholeStringMeasurement(text: String) {
        let meter = ContentHeightMeter()
        let width: CGFloat = 300
        let sum = meter.height(of: text as NSString, width: width, attributes: attributes)
        #expect(
            abs(sum - wholeStringHeight(text, width: width)) < 0.5,
            "height differs for \(text.prefix(20).debugDescription)"
        )
    }

    @Test func aLargeMixedScriptDocumentIsMeasuredInWellUnderASecond() {
        let line = "日本語のテキストと emoji 🎉 が混在する行です。これはテストです。"
        let text = (0 ..< 3000).map { "\($0) " + line }.joined(separator: "\n")
        let meter = ContentHeightMeter()
        let start = ContinuousClock.now

        let height = meter.height(of: text as NSString, width: 700, attributes: attributes)

        #expect(height > 0)
        // The whole-string measurement of this takes minutes; allow a very generous bound.
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    @Test func aRepeatMeasurementReusesTheCachedParagraphs() {
        let text = (0 ..< 500).map { "line \($0) with some text" }.joined(separator: "\n")
        let meter = ContentHeightMeter()
        let first = meter.height(of: text as NSString, width: 400, attributes: attributes)
        let again = meter.height(of: text as NSString, width: 400, attributes: attributes)
        #expect(first == again)
    }

    @Test func aWidthChangeInvalidatesTheCache() {
        let text = String(repeating: "word ", count: 200)
        let meter = ContentHeightMeter()
        let narrow = meter.height(of: text as NSString, width: 150, attributes: attributes)
        let wide = meter.height(of: text as NSString, width: 600, attributes: attributes)
        #expect(narrow > wide)
    }

    /// Review pass 6: the meter re-enumerated, copied and hashed every paragraph of the document after each edit
    /// pause (~0.7 s per pause for a 10 MB file in release), and one huge CJK paragraph was still quadratic.
    @Test func aHugeDocumentIsEstimatedNotMeasuredParagraphByParagraph() {
        let text = (0 ..< 130_000).map { "line number \($0) with some distinct text" }.joined(separator: "\n")
        #expect(text.utf16.count > ContentHeightMeter.estimationThreshold)
        let meter = ContentHeightMeter()
        let start = ContinuousClock.now

        let height = meter.height(of: text as NSString, width: 700, attributes: attributes)

        #expect(height > 130_000 * 10)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func oneHugeParagraphIsEstimatedInsteadOfMeasured() {
        let text = String(repeating: "日本語のテキスト🙂", count: 30000)
        #expect(text.utf16.count > ContentHeightMeter.maximumMeasuredParagraphLength)
        let meter = ContentHeightMeter()
        let start = ContinuousClock.now

        let height = meter.height(of: text as NSString, width: 700, attributes: attributes)

        #expect(height > 0)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func estimatedWordsAndForcedBreaksSurviveUTF16ChunkBoundaries() {
        let width: CGFloat = 1000
        let length = HeightParagraphScanner.chunkCapacity + 1
        let word = String(repeating: "a", count: length)
        let source = word + "\u{2028}" + word
        let estimator = LineHeightEstimator(width: width, attributes: attributes)
        let advance = max(("n" as NSString).size(withAttributes: attributes).width, 1)
        let lineHeight = ceil(("Ag" as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes
        ).height)
        let expectedLines = 2 + 2 * Int((CGFloat(length) * advance / width).rounded(.down))
        #expect(estimator.height(of: source as NSString,
                                 range: NSRange(location: 0, length: (source as NSString).length))
                == CGFloat(expectedLines) * lineHeight)
    }

    /// Review pass 7: the first estimate ignored the paragraph style's line-height multiple and priced every unit at
    /// the width of "n", so CJK/emoji text was under-estimated and the last 19-48% of such a document could not be
    /// scrolled to. The estimate must never be shorter than the real layout.
    @Test(arguments: [
        String(repeating: "word and more words ", count: 400),
        String(repeating: "日本語のテキストと混在する行です。", count: 300),
        String(repeating: "emoji 🙂🎉 and 日本 mixed ", count: 250),
        String(repeating: "a", count: 5000),
        // Review pass 8: forced breaks the meter does not split on, tabs, and long words.
        (0 ..< 400).map { "line \($0)" }.joined(separator: "\u{2028}"),
        (0 ..< 400).map { "line \($0)" }.joined(separator: "\u{85}"),
        String(repeating: "a\t", count: 1500),
        String(repeating: String(repeating: "w", count: 36) + " ", count: 300),
    ])
    func theEstimateIsNeverShorterThanTheMeasurementAndNotWildlyLonger(text: String) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        let styled: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .paragraphStyle: style,
        ]
        let width: CGFloat = 500
        let nsText = text as NSString
        let measured = nsText.boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: styled
        ).height

        let estimated = LineHeightEstimator(width: width, attributes: styled)
            .height(of: nsText, range: NSRange(location: 0, length: nsText.length))

        #expect(estimated >= measured, "estimate \(estimated) is shorter than the layout \(measured)")
        #expect(estimated < measured * 2.5, "estimate \(estimated) is far longer than the layout \(measured)")
    }

    /// Review pass 9: single-unit symbols/emoji (⌚ ✅ ❌) are wider than an em and `w`/`m`/`W` are far wider than `n`
    /// in a proportional font; the estimate priced them at 1 em / the width of "n" and fell ~48% short.
    @Test(arguments: [
        String(repeating: "⌚✅", count: 800),
        String(repeating: "wwwwwww mmmmmmm ", count: 300),
        String(repeating: "WIDE CAPITAL LETTERS AND MORE ", count: 200),
    ])
    func theEstimateCoversSingleUnitEmojiAndWideProportionalGlyphs(text: String) throws {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        for font in try [
            NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            #require(NSFont(name: "Helvetica", size: 13)),
        ] {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
            let nsText = text as NSString
            let measured = nsText.boundingRect(
                with: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height

            let estimated = LineHeightEstimator(width: 500, attributes: attributes)
                .height(of: nsText, range: NSRange(location: 0, length: nsText.length))

            #expect(estimated >= measured, "\(font.fontName): estimate \(estimated) < layout \(measured)")
            #expect(estimated < measured * 2.5, "\(font.fontName): estimate \(estimated) far above \(measured)")
        }
    }
}
