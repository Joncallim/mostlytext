import AppKit
import CryptoKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import Neon
import SwiftUI
import Testing
import Themes

/// Opt-in, source-bound Release measurement. A style callback or TextKit
/// attribute alone is not the endpoint: each edit reaches an ordered mounted
/// window's AppKit display and a bounded bitmap readback. This is still a
/// hosted display readback, not a photographed physical monitor or V1 receipt.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_DISPLAY_BENCH"] == "1"))
// swiftlint:disable:next type_body_length
struct ViewportDisplayBudgetBenchmarkTests {
    private struct EditCase {
        let name: String
        let anchor: String
        let offset: Int
        let length: Int
        let replacement: String

        func range(in source: NSString) throws -> NSRange {
            let found = source.range(of: anchor)
            try #require(found.location != NSNotFound, "Missing unique case anchor: \(name)")
            try #require(source.range(of: anchor, options: [], range: NSRange(
                location: NSMaxRange(found), length: source.length - NSMaxRange(found)
            )).location == NSNotFound, "Ambiguous case anchor: \(name)")
            return NSRange(location: found.location + offset, length: length)
        }
    }

    private static let cases: [EditCase] = [
        .init(name: "begin-word", anchor: "alphaStart", offset: 5, length: 0, replacement: "X"),
        .init(name: "middle-word", anchor: "alphaMiddle", offset: 5, length: 0, replacement: "Y"),
        .init(name: "end-word", anchor: "alphaEnd", offset: 5, length: 0, replacement: "Z"),
        .init(name: "begin-delete", anchor: "alphaXStart", offset: 5, length: 1, replacement: ""),
        .init(name: "word-boundary", anchor: "alphaYMiddle", offset: 12, length: 0, replacement: " "),
        .init(name: "unicode-replacement", anchor: "café", offset: 3, length: 1, replacement: "e\u{301}"),
        .init(name: "crlf-replacement", anchor: "CRLF_MARKER\r\n", offset: 11, length: 2, replacement: "\n"),
        .init(name: "structural-newline", anchor: "alphaStart", offset: 5, length: 0, replacement: "\n"),
        .init(name: "replacement-shrink", anchor: "uniqueTailReplacementMarker", offset: 0,
              length: 27, replacement: "uniqueTail"),
        .init(name: "replacement-grow", anchor: "uniqueTail", offset: 0,
              length: 10, replacement: "uniqueTailReplacementMarker"),
    ]

    @Test(.timeLimit(.minutes(8)))
    // swiftlint:disable:next function_body_length
    func fullSizeProductionInputToMountedDisplay() async throws {
        let filler = HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 530_000)
        let original = "# alphaStart heading\n\n## CRLF_MARKER\r\n**café** 😊 **bold**\r\n\r\n"
            + filler + "\n\n## alphaMiddle heading\n\n" + filler
            + "\n\n`alphaEnd` and **uniqueTailReplacementMarker**\n"
        try #require(original.utf8.count >= 1 << 20)
        try #require((original as NSString).length < NeonSyntaxHighlighter.viewportMaxUTF16Units)
        let model = DisplayBudgetSourceBox(original)
        let identity = UUID().uuidString
        let editorStore = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            identity: identity, configuration: .default, store: editorStore
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close(); editorStore.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(editorStore.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 800, height: 50000)
        scroll.layoutSubtreeIfNeeded()
        try #require(window.isVisible && system.textView.window === window)

        let syntaxStore = SyntaxHighlightStore()
        let highlighter = try #require(syntaxStore.highlighter(
            for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
        ) as? NeonSyntaxHighlighter)
        defer { syntaxStore.evictAll() }
        try #require(highlighter.state.isVisibleOnly)
        let session = try #require(highlighter.viewportSession)
        let painter = try #require(highlighter.viewportPainter)
        await session.waitForPendingParse()
        try #require(!session.visibleTokens().isEmpty)

        var timing: [(MarkdownViewportSession.TimingEvent, UInt64)] = []
        session.onTimingEvent = { event, time in timing.append((event, time)) }
        var results: [[String: Any]] = []
        let registry = GrammarRegistry()
        for edit in Self.cases {
            let beforeSource = system.textView.string as NSString
            let range = try edit.range(in: beforeSource)
            let expectedSource = beforeSource.replacingCharacters(in: range, with: edit.replacement)
            // Independent full parse occurs before the timed input. Its cost is
            // excluded from the product path and retained only as an oracle.
            let snapshot = try MarkdownSectionParser.snapshot(source: expectedSource, registry: registry)
            let oracle = try MarkdownSectionCache(source: expectedSource, snapshot: snapshot)
            let anchorRange = beforeSource.range(of: edit.anchor)
            system.textView.setSelectedRange(NSRange(location: range.location, length: 0))
            system.scrollToVisible(utf16Range: anchorRange)
            scroll.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            // Capture the edited line, including following glyphs. A space
            // inserted after the anchor shifts those glyphs even when the
            // anchor's own pixels remain identical.
            let editedLine = beforeSource.lineRange(for: NSRange(location: range.location, length: 0))
            let captureRange = NSRange(location: editedLine.location, length: min(80, editedLine.length))
            let displayRegion = try Self.targetRegion(host: host, window: window,
                                                      textView: system.textView, range: captureRange)
            let beforePixels = try Self.displayReadback(host: host, window: window, region: displayRegion)
            let priorValidation = painter.validationPassCount
            timing.removeAll(keepingCapacity: true)

            let input = DispatchTime.now().uptimeNanoseconds
            system.textView.insertText(edit.replacement, replacementRange: range)
            let storageReturned = DispatchTime.now().uptimeNanoseconds
            await session.waitForPendingParse()
            let deadline = input + 5_000_000_000
            var styled = false
            var matchedPaint: AccentPaint?
            var styleReadback = DispatchTime.now().uptimeNanoseconds
            while DispatchTime.now().uptimeNanoseconds < deadline {
                await Task.yield()
                guard let visible = system.visibleUTF16Range else { continue }
                let painted = try Self.accentPaint(in: visible, oracle: oracle, theme: BundledThemes.light)
                let actual = Self.renderedAccentRanges(in: system.textView, clippedTo: visible,
                                                       buckets: painted.buckets)
                if painted.buckets.contains(where: { !$0.expected.isEmpty }),
                   painter.validationPassCount > priorValidation,
                   actual.indices.allSatisfy({ actual[$0].subtracting(painted.ambiguous)
                           == painted.buckets[$0].expected }) {
                    styled = true
                    matchedPaint = painted
                    styleReadback = DispatchTime.now().uptimeNanoseconds
                    break
                }
            }
            try #require(styled, "Current oracle ranges never appeared in TextKit: \(edit.name)")
            let painted = try #require(matchedPaint)
            let afterPixels = try Self.displayReadback(host: host, window: window, region: displayRegion)
            let displayReadback = afterPixels.completedAt
            let accentPixels = Self.accentPixelSamples(painted: painted, bitmap: afterPixels.bitmap,
                                                       textView: system.textView, host: host,
                                                       region: displayRegion)
            try #require(accentPixels > 0, "No oracle accent glyph pixels in mounted display: \(edit.name)")
            try #require(afterPixels.nonBackgroundSamples > 2, "Blank edited-glyph display: \(edit.name)")
            let pixelChanged = beforePixels.digest != afterPixels.digest
            // CRLF/LF and NFC/NFD are different source/parse states but can
            // draw identical glyphs. Oracle accent and nonblank display checks
            // still apply; a pixel-delta requirement would reject correct rendering.
            if edit.name != "crlf-replacement", edit.name != "unicode-replacement" {
                try #require(pixelChanged, "Mounted display pixels did not change after input: \(edit.name)")
            }
            try #require(Array(system.textView.string.utf16) == Array(expectedSource.utf16),
                         "Authored UTF-16 changed unexpectedly: \(edit.name)")
            try #require(Array(model.text.utf16) == Array(expectedSource.utf16),
                         "SwiftUI binding differs from editor: \(edit.name)")
            try #require(highlighter.state.isVisibleOnly)

            func event(_ sought: MarkdownViewportSession.TimingEvent) -> UInt64? {
                timing.first { $0.0 == sought }?.1
            }
            let storageEvent = try #require(event(.storageEdit))
            let parseRequested = try #require(event(.parseRequested))
            let parseResolved = try #require(event(.parseResolved))
            let published = try #require(event(.published))
            let milliseconds = { (start: UInt64, end: UInt64) -> Double in
                Double(end - start) / 1_000_000
            }
            let total = milliseconds(input, displayReadback)
            results.append([
                "case": edit.name,
                "source_utf8_bytes": expectedSource.utf8.count,
                "source_utf16_units": (expectedSource as NSString).length,
                "input_to_storage_return_ms": milliseconds(input, storageReturned),
                "input_to_storage_event_ms": milliseconds(input, storageEvent),
                "storage_event_to_parse_request_ms": milliseconds(storageEvent, parseRequested),
                "queue_plus_parse_ms": milliseconds(parseRequested, parseResolved),
                "parse_resolution_to_publication_ms": milliseconds(parseResolved, published),
                "publication_to_style_readback_ms": milliseconds(published, styleReadback),
                "style_to_display_return_ms": milliseconds(styleReadback, afterPixels.displayReturnedAt),
                "display_return_to_bitmap_readback_ms": milliseconds(afterPixels.displayReturnedAt, displayReadback),
                "input_to_display_return_ms": milliseconds(input, afterPixels.displayReturnedAt),
                "style_to_display_readback_ms": milliseconds(styleReadback, displayReadback),
                "input_to_display_readback_ms": total,
                "under_50_ms": total < 50,
                "pixel_changed": pixelChanged,
                "display_sha256": afterPixels.digest,
                "display_non_background_samples": afterPixels.nonBackgroundSamples,
                "oracle_accent_pixel_samples": accentPixels,
                "full_parse_count": session.fullParseCount,
                "local_parse_count": session.localParseCount,
            ])
        }
        let body = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        let encoded = try #require(String(data: body, encoding: .utf8))
        print("VIEWPORT-DISPLAY-BUDGET " + encoded)
        #expect(results.count == Self.cases.count)
        // A complete measurement may reveal a product-budget failure. The
        // workflow records every such case; it never calls that a budget pass.
    }

    private struct Pixels {
        let displayReturnedAt: UInt64
        let completedAt: UInt64
        let digest: String
        let nonBackgroundSamples: Int
        let bitmap: NSBitmapImageRep
    }

    private struct AccentBucket {
        let color: NSColor
        var expected: IndexSet
    }

    private struct AccentPaint {
        let buckets: [AccentBucket]
        let ambiguous: IndexSet
    }

    private static func targetRegion(host: NSHostingView<EditorView>, window: NSWindow,
                                     textView: NSTextView, range: NSRange) throws -> NSRect {
        let screen = textView.firstRect(forCharacterRange: range, actualRange: nil)
        let inWindow = window.convertFromScreen(screen)
        let inHost = host.convert(inWindow, from: nil).insetBy(dx: -5, dy: -5)
        let bounded = inHost.intersection(host.bounds).integral
        try #require(bounded.width >= 5 && bounded.height >= 5,
                     "Edited text is not within the mounted display")
        return bounded
    }

    private static func displayReadback(host: NSHostingView<EditorView>, window: NSWindow,
                                        region: NSRect) throws -> Pixels {
        window.displayIfNeeded()
        let displayReturnedAt = DispatchTime.now().uptimeNanoseconds
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: region))
        host.cacheDisplay(in: region, to: bitmap)
        let completedAt = DispatchTime.now().uptimeNanoseconds
        let raw = try #require(bitmap.bitmapData)
        let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
        let digest = SHA256.hash(data: Data(bytes: raw, count: byteCount))
            .map { String(format: "%02x", $0) }.joined()
        var ink = 0
        for pixelY in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for pixelX in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.sRGB) else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.75 {
                    ink += 1
                }
            }
        }
        return Pixels(displayReturnedAt: displayReturnedAt, completedAt: completedAt,
                      digest: digest, nonBackgroundSamples: ink, bitmap: bitmap)
    }

    /// Inspect bitmap pixels inside a glyph rectangle that the independent
    /// oracle assigns a specific non-base accent. This remains an AppKit
    /// bitmap sample, not evidence of physical compositor presentation.
    private static func accentPixelSamples(painted: AccentPaint, bitmap: NSBitmapImageRep,
                                           textView: NSTextView, host: NSHostingView<EditorView>,
                                           region: NSRect) -> Int {
        guard let window = textView.window,
              let base = BundledThemes.light.chrome.foreground.nsColor.usingColorSpace(.sRGB)
        else { return 0 }
        let pixelsPerPointX = CGFloat(bitmap.pixelsWide) / region.width
        let pixelsPerPointY = CGFloat(bitmap.pixelsHigh) / region.height
        for bucket in painted.buckets where !bucket.expected.isEmpty {
            // Some theme classes are almost the base foreground. Require a
            // clearly distinct accent so antialiased base glyphs cannot pass.
            guard let target = bucket.color.usingColorSpace(.sRGB),
                  visiblyDistinct(target, from: base) else { continue }
            for span in bucket.expected.rangeView {
                let probe = NSRange(location: span.lowerBound, length: min(12, span.count))
                let screen = textView.firstRect(forCharacterRange: probe, actualRange: nil)
                let glyphRect = host.convert(window.convertFromScreen(screen), from: nil)
                    .intersection(region)
                guard glyphRect.width >= 2, glyphRect.height >= 2 else { continue }
                let minX = max(0, Int((glyphRect.minX - region.minX) * pixelsPerPointX))
                let maxX = min(bitmap.pixelsWide, Int(ceil((glyphRect.maxX - region.minX) * pixelsPerPointX)))
                let minY = max(0, Int((glyphRect.minY - region.minY) * pixelsPerPointY))
                let maxY = min(bitmap.pixelsHigh, Int(ceil((glyphRect.maxY - region.minY) * pixelsPerPointY)))
                for pixelX in minX ..< maxX {
                    for pixelY in minY ..< maxY {
                        // AppKit view/bitmap origin conventions can differ;
                        // accept either vertical orientation within this
                        // tightly bounded oracle glyph rectangle.
                        for imageY in [pixelY, bitmap.pixelsHigh - 1 - pixelY] {
                            guard let sample = bitmap.colorAt(x: pixelX, y: imageY)?.usingColorSpace(.sRGB) else {
                                continue
                            }
                            if abs(sample.redComponent - target.redComponent) < 0.16,
                               abs(sample.greenComponent - target.greenComponent) < 0.16,
                               abs(sample.blueComponent - target.blueComponent) < 0.16 {
                                return 1
                            }
                        }
                    }
                }
            }
        }
        return 0
    }

    private static func visiblyDistinct(_ accent: NSColor, from base: NSColor) -> Bool {
        max(abs(accent.redComponent - base.redComponent),
            max(abs(accent.greenComponent - base.greenComponent),
                abs(accent.blueComponent - base.blueComponent))) > 0.3
    }

    /// Compare only theme accents. Base text also has a foreground color, so
    /// treating every colored range as syntax would give a false paint pass.
    /// Differently styled overlapping captures are excluded because their
    /// final TextKit precedence is not independently specified by this oracle.
    private static func accentPaint(in visible: NSRange, oracle: MarkdownSectionCache,
                                    theme: Theme) throws -> AccentPaint {
        let base = theme.chrome.foreground
        var ambiguous = IndexSet()
        var previous: [(range: NSRange, color: ThemeColor)] = []
        var semanticColors: [ThemeColor] = []
        for color in theme.tokenStyles.values.map(\.color) where color != base {
            if !semanticColors.contains(color) {
                semanticColors.append(color)
            }
        }
        var buckets = semanticColors.map { AccentBucket(color: $0.nsColor, expected: IndexSet()) }
        for token in try oracle.tokens(in: visible) {
            let clipped = NSIntersectionRange(token.range, visible)
            guard clipped.length > 0 else { continue }
            let color = theme.style(for: token.name)?.color ?? base
            for prior in previous where prior.color != color {
                let overlap = NSIntersectionRange(prior.range, clipped)
                if overlap.length > 0 {
                    ambiguous.insert(integersIn: overlap.location ..< NSMaxRange(overlap))
                }
            }
            previous.append((clipped, color))
            if color != base, let index = semanticColors.firstIndex(of: color) {
                buckets[index].expected.insert(integersIn: clipped.location ..< NSMaxRange(clipped))
            }
        }
        for index in buckets.indices {
            buckets[index].expected.subtract(ambiguous)
        }
        return AccentPaint(buckets: buckets, ambiguous: ambiguous)
    }

    private static func renderedAccentRanges(in textView: NSTextView, clippedTo visible: NSRange,
                                             buckets: [AccentBucket]) -> [IndexSet] {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: visible.location)
        else { return Array(repeating: IndexSet(), count: buckets.count) }
        let origin = content.documentRange.location
        var ranges = Array(repeating: IndexSet(), count: buckets.count)
        layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, textRange in
            let location = content.offset(from: origin, to: textRange.location)
            if location >= NSMaxRange(visible) {
                return false
            }
            guard let color = attributes[.foregroundColor] as? NSColor,
                  let index = buckets.firstIndex(where: { $0.color.isEqual(color) }) else { return true }
            let length = content.offset(from: textRange.location, to: textRange.endLocation)
            let clipped = NSIntersectionRange(NSRange(location: location, length: length), visible)
            if clipped.length > 0 {
                ranges[index].insert(integersIn: clipped.location ..< NSMaxRange(clipped))
            }
            return true
        }
        return ranges
    }
}

@MainActor
private final class DisplayBudgetSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
