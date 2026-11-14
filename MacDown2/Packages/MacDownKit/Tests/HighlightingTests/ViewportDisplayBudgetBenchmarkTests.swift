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
        let original = "# alphaStart heading\n\nCRLF_MARKER\r\ncafé 😊 **bold**\r\n\r\n"
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
            let displayRegion = try Self.targetRegion(host: host, window: window,
                                                      textView: system.textView, range: anchorRange)
            let beforePixels = try Self.displayReadback(host: host, window: window, region: displayRegion)
            let priorValidation = painter.validationPassCount
            timing.removeAll(keepingCapacity: true)

            let input = DispatchTime.now().uptimeNanoseconds
            system.textView.insertText(edit.replacement, replacementRange: range)
            let storageReturned = DispatchTime.now().uptimeNanoseconds
            await session.waitForPendingParse()
            let deadline = input + 5_000_000_000
            var styled = false
            var styleReadback = DispatchTime.now().uptimeNanoseconds
            while DispatchTime.now().uptimeNanoseconds < deadline {
                await Task.yield()
                guard let visible = system.visibleUTF16Range else { continue }
                let expectedRanges = try Self.coalesced(oracle.tokens(in: visible).map(\.range))
                let actualRanges = Self.renderedRanges(in: system.textView, clippedTo: visible)
                if !expectedRanges.isEmpty, painter.validationPassCount > priorValidation,
                   actualRanges == expectedRanges {
                    styled = true
                    styleReadback = DispatchTime.now().uptimeNanoseconds
                    break
                }
            }
            try #require(styled, "Current oracle ranges never appeared in TextKit: \(edit.name)")
            let afterPixels = try Self.displayReadback(host: host, window: window, region: displayRegion)
            let displayReadback = afterPixels.completedAt
            try #require(afterPixels.nonBackgroundSamples > 2, "Blank edited-glyph display: \(edit.name)")
            try #require(beforePixels.digest != afterPixels.digest,
                         "Mounted display pixels did not change after input: \(edit.name)")
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
                "style_to_display_readback_ms": milliseconds(styleReadback, displayReadback),
                "input_to_display_readback_ms": total,
                "under_50_ms": total < 50,
                "display_sha256": afterPixels.digest,
                "display_non_background_samples": afterPixels.nonBackgroundSamples,
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
        let completedAt: UInt64
        let digest: String
        let nonBackgroundSamples: Int
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
        return Pixels(completedAt: completedAt, digest: digest, nonBackgroundSamples: ink)
    }

    private static func renderedRanges(in textView: NSTextView, clippedTo visible: NSRange) -> [NSRange] {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: visible.location)
        else { return [] }
        let origin = content.documentRange.location
        var ranges: [NSRange] = []
        layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, textRange in
            let location = content.offset(from: origin, to: textRange.location)
            if location >= NSMaxRange(visible) {
                return false
            }
            guard attributes[.foregroundColor] is NSColor else { return true }
            let length = content.offset(from: textRange.location, to: textRange.endLocation)
            let clipped = NSIntersectionRange(NSRange(location: location, length: length), visible)
            if clipped.length > 0 {
                ranges.append(clipped)
            }
            return true
        }
        return coalesced(ranges)
    }

    private static func coalesced(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in sorted {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSRange(location: last.location,
                                                   length: max(NSMaxRange(last), NSMaxRange(range)) - last.location)
            } else {
                result.append(range)
            }
        }
        return result
    }
}

@MainActor
private final class DisplayBudgetSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
