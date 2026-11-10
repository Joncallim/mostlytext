import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3b-iv — Rectangular (column) selection via Option-drag
/// (§6.10).
@MainActor
@Suite("EditorTextSystem rectangular selection (Slice 3b-iv)")
struct EditorRectangularSelectionTests {
    private struct Mounted {
        let system: EditorTextSystem
        let textView: EditorTextView
        let window: NSWindow
    }

    private func mount(text: String, width: CGFloat = 400) throws -> Mounted {
        let system = EditingAssistIntegrationSupport.makeSystem(text: text)
        let textView = try #require(system.textView as? EditorTextView)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        scrollView.documentView = textView
        system.scrollView = scrollView
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 300)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        textView.layoutSubtreeIfNeeded()
        return Mounted(system: system, textView: textView, window: window)
    }

    /// The view-space point (NOT window/screen space) at `offset`, via the
    /// same `firstRect(forCharacterRange:)` this codebase already trusts
    /// (`EditorTextView.drawSecondaryCarets`, `EditorOptionClickTests`).
    private func viewPoint(at offset: Int, in mounted: Mounted, edge: CGFloat = 0) throws -> CGPoint {
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let screenRect = mounted.textView.firstRect(
            forCharacterRange: NSRange(location: offset, length: 0),
            actualRange: &actualRange
        )
        #expect(actualRange.location != NSNotFound)
        let screenPoint = NSPoint(x: screenRect.minX + edge, y: screenRect.midY)
        let windowPoint = mounted.window.convertPoint(fromScreen: screenPoint)
        return mounted.textView.convert(windowPoint, from: nil)
    }

    // MARK: - Pure geometry: `rectangularSelectionRanges(fromViewPoint:toViewPoint:)`

    @Test func aRectangleSpanningThreeLinesProducesOneRangePerLine() throws {
        let mounted = try mount(text: "one\ntwo\nthree")
        let start = try viewPoint(at: 0, in: mounted) // line 1, column 1
        let end = try viewPoint(at: 11, in: mounted) // line 3 ("thr|ee"), column 3

        let ranges = mounted.system.rectangularSelectionRanges(fromViewPoint: start, toViewPoint: end)

        #expect(ranges?.count == 3)
    }

    @Test func aRectangleWithHorizontalExtentClampsEachLineToItsOwnLength() throws {
        // A ragged block: middle line is much shorter than the rectangle's
        // own right edge -- §6.10's own required "drag that starts or ends
        // past either end of a line" coverage.
        let mounted = try mount(text: "one two three\nab\nfour five six")
        // Anchor before "one" (column 1, line 1); drag to well past "four
        // five six"'s own end on line 3 (column large).
        let start = try viewPoint(at: 0, in: mounted)
        let end = try viewPoint(at: 29, in: mounted, edge: 400) // far past line 3's own end

        let ranges = try #require(mounted.system.rectangularSelectionRanges(fromViewPoint: start, toViewPoint: end))

        #expect(ranges.count == 3)
        // Line 2 ("ab") is only 2 characters -- clamps to its own end
        // (offset 14 + 2 = 16), never spilling onto line 3.
        let line2 = ranges[1]
        #expect(line2.location + line2.length == 16)
    }

    @Test func aRectangleAcrossWrappedContinuationLinesProducesOneRangePerVisualLine() throws {
        // Force real wrapping: a narrow view + one long, unbroken paragraph.
        let mounted = try mount(text: String(repeating: "word ", count: 20), width: 120)
        // Offsets 0 and 20 are both within the SAME paragraph (no "\n"
        // anywhere in this text) but land on different WRAPPED lines given
        // the narrow width -- confirmed by the offset-to-point round trip
        // itself landing at visibly different Y coordinates below.
        let start = try viewPoint(at: 0, in: mounted)
        let end = try viewPoint(at: 20, in: mounted)
        #expect(start.y != end.y, "fixture must actually wrap for this test to mean anything")

        let ranges = mounted.system.rectangularSelectionRanges(fromViewPoint: start, toViewPoint: end)

        // One range per WRAPPED VISUAL line spanned, not one range for the
        // whole paragraph -- the defining behavior of "per-line-fragment
        // geometry" this contract requires.
        #expect((ranges?.count ?? 0) >= 2)
    }

    @Test func aPurelyVerticalDragProducesABareCaretOnEveryLine() throws {
        // Left and right edges of the rectangle coincide (no horizontal
        // extent): every spanned line should get a zero-length caret at
        // the same column, not a real selection.
        let mounted = try mount(text: "one\ntwo\nthree")
        let start = try viewPoint(at: 1, in: mounted) // line 1, column 2
        let end = try viewPoint(at: 9, in: mounted) // line 3, column 2 (same x)

        let ranges = try #require(mounted.system.rectangularSelectionRanges(fromViewPoint: start, toViewPoint: end))

        #expect(ranges.count == 3)
        #expect(ranges.allSatisfy { $0.length == 0 })
    }

    @Test func aSingleLineDragIsNotASpecialCase() throws {
        let mounted = try mount(text: "one two three")
        let start = try viewPoint(at: 0, in: mounted)
        let end = try viewPoint(at: 7, in: mounted)

        let ranges = mounted.system.rectangularSelectionRanges(fromViewPoint: start, toViewPoint: end)

        #expect(ranges?.count == 1)
    }

    @Test func draggingFromAbovethefirstLineStillResolvesTheFirstLine() throws {
        let mounted = try mount(text: "one\ntwo\nthree")
        let inset = mounted.textView.textContainerInset
        // A point above the document's own top edge (negative container-
        // space Y) -- a real, ordinary starting point if the click lands in
        // the text view's own top inset padding.
        let aboveDocument = CGPoint(x: inset.width, y: -50)
        let end = try viewPoint(at: 9, in: mounted) // line 3

        let ranges = mounted.system.rectangularSelectionRanges(fromViewPoint: aboveDocument, toViewPoint: end)

        #expect(ranges?.count == 3, "dragging from above the first line must still include it, not silently drop it")
    }

    @Test func tabStopsResolveByActualGlyphGeometryNotNaiveCharacterCounting() throws {
        // A tab's rendered width is not one character-cell wide -- if the
        // rectangle's edges were resolved by counting characters instead of
        // using the real laid-out geometry `characterIndex(for:)` already
        // provides, this would silently pick the wrong offset.
        let mounted = try mount(text: "a\tbbbbbbbb\nsecond line")
        // Click exactly at the character right after the tab on line 1
        // (offset 2, "a\t|bbbbbbbb") via its own real geometry, then drag
        // straight down to the same X on line 2.
        let afterTab = try viewPoint(at: 2, in: mounted)
        let below = CGPoint(x: afterTab.x, y: afterTab.y + 20)

        let ranges = try #require(mounted.system.rectangularSelectionRanges(
            fromViewPoint: afterTab,
            toViewPoint: below
        ))

        #expect(ranges.count == 2)
        // Line 1's own range must land exactly back at offset 2 (a
        // zero-width vertical drag) -- proving the real glyph geometry
        // round-trips exactly through the tab, not merely "close enough."
        #expect(ranges[0] == NSRange(location: 2, length: 0))
    }

    @Test func reversingTheDragDirectionProducesTheSameRangesButADifferentPrimary() throws {
        let mounted = try mount(text: "one\ntwo\nthree")
        let top = try viewPoint(at: 0, in: mounted)
        let bottom = try viewPoint(at: 9, in: mounted)

        #expect(mounted.system.applyRectangularSelection(fromViewPoint: top, toViewPoint: bottom))
        let downwardRanges = mounted.system.selectionSet.ranges
        let downwardPrimary = mounted.system.selectionSet.primaryRange

        #expect(mounted.system.applyRectangularSelection(fromViewPoint: bottom, toViewPoint: top))
        let upwardRanges = mounted.system.selectionSet.ranges
        let upwardPrimary = mounted.system.selectionSet.primaryRange

        #expect(downwardRanges == upwardRanges, "the same rectangle's ranges must not depend on drag direction")
        // The primary follows wherever the mouse currently is (`toViewPoint`):
        // dragging downward, the primary is the bottom line; dragging
        // upward from the same two points, it's the top line.
        #expect(downwardPrimary.location > upwardPrimary.location)
    }

    // MARK: - `applyRectangularSelection` replacing `selectionSet` wholesale

    @Test func applyingReplacesAnyPriorUnrelatedSelectionEntirely() throws {
        let mounted = try mount(text: "one\ntwo\nthree")
        mounted.system.toggleSecondaryCaret(at: 12) // an unrelated caret on line 3
        #expect(mounted.system.selectionSet.isMultiple)

        let start = try viewPoint(at: 0, in: mounted)
        let end = try viewPoint(at: 4, in: mounted)
        let handled = mounted.system.applyRectangularSelection(fromViewPoint: start, toViewPoint: end)

        #expect(handled)
        #expect(mounted.system.selectionSet.count == 2, "must be exactly the rectangle's own 2 lines, not 3")
    }

    // MARK: - A ragged rectangle's interaction with multi-selection typing/delete

    @Test func aRaggedRectangleInsertsAtSelectionsAndBareCarets() throws {
        // A short middle line produces a bare caret alongside real
        // selections. The insertion transaction must handle all three.
        let mounted = try mount(text: "one two three\nab\nfour five six")
        // The LEFT edge (column 5, offset 4) is already past "ab"'s own
        // 2-character length, so line 2 clamps to a zero-length caret at
        // its own end on BOTH sides -- unlike a left edge at column 1,
        // which would still land WITHIN "ab" and produce a real (if short)
        // selection there instead of a bare caret.
        let start = try viewPoint(at: 4, in: mounted)
        let end = try viewPoint(at: 29, in: mounted, edge: 400) // far past line 3's own end

        #expect(mounted.system.applyRectangularSelection(fromViewPoint: start, toViewPoint: end))
        let ranges = mounted.system.selectionSet.ranges
        #expect(ranges.count == 3)
        #expect(ranges.contains { $0.length == 0 }, "fixture must actually be ragged for this test to mean anything")
        #expect(ranges.contains { $0.length > 0 })

        #expect(mounted.system.applyMultiCursorInsert("X"))
        #expect(mounted.system.text == "one X\nabX\nfourX")
        #expect(mounted.system.selectionSet.ranges == [
            NSRange(location: 5, length: 0),
            NSRange(location: 9, length: 0),
            NSRange(location: 15, length: 0),
        ])
    }

    @Test func aRaggedRectangleStillDeclinesDirectionlessMultiCursorDelete() throws {
        let mounted = try mount(text: "one two three\nab\nfour five six")
        let start = try viewPoint(at: 4, in: mounted)
        let end = try viewPoint(at: 29, in: mounted, edge: 400)

        #expect(mounted.system.applyRectangularSelection(fromViewPoint: start, toViewPoint: end))
        let ranges = mounted.system.selectionSet.ranges
        #expect(ranges.contains { $0.length == 0 })
        #expect(!mounted.system.applyMultiCursorDeleteSelection())
        #expect(mounted.system.selectionSet.ranges == ranges)
        #expect(mounted.system.text == "one two three\nab\nfour five six")
    }

    // MARK: - Real `mouseDown`/`mouseDragged` + `finishRectangularSelectionGesture`

    //
    // `mouseUp(with:)` itself is deliberately never driven directly here,
    // for the same reason `EditorOptionClickTests` never drives a real,
    // non-Option `mouseDown(with:)`: found empirically, during this
    // slice's own development, that `NSTextView.mouseUp(with:)`'s real
    // implementation can also hang a headless test past its timeout
    // against an isolated synthetic event. `finishRectangularSelectionGesture`
    // is `mouseUp`'s own logic with the risky `super` call extracted out —
    // see its doc comment — so these tests exercise the exact same logic
    // without that risk.

    @Test func aRealOptionDragPastTheThresholdReplacesTheInitialToggleWithARectangle() throws {
        let mounted = try mount(text: "one\ntwo\nthree")
        mounted.system.selectedRange = NSRange(location: 0, length: 0)
        let down = try viewPoint(at: 0, in: mounted)
        let dragTo = try viewPoint(at: 9, in: mounted)

        try mounted.textView.mouseDown(with: syntheticEvent(.leftMouseDown, at: down, in: mounted, modifiers: .option))
        // The plain-click toggle already fired here (adds a caret at
        // offset 0) -- the drag below must discard it, not layer on top.
        try mounted.textView.mouseDragged(with: syntheticEvent(
            .leftMouseDragged,
            at: dragTo,
            in: mounted,
            modifiers: .option
        ))
        mounted.textView.finishRectangularSelectionGesture(atViewPoint: dragTo)

        #expect(
            mounted.system.selectionSet.count == 3,
            "one range per line the rectangle spans, not the single toggled caret"
        )
    }

    @Test func aRealOptionClickWithNoSubsequentDragLeavesTheToggleAsFinal() throws {
        // The bug this slice's own review caught before it shipped: a plain
        // click's mouseUp must NOT recompute a degenerate one-point
        // "rectangle" and silently discard the toggle that already ran.
        let mounted = try mount(text: "one two three")
        mounted.system.selectedRange = NSRange(location: 0, length: 0)
        let point = try viewPoint(at: 8, in: mounted)

        try mounted.textView.mouseDown(with: syntheticEvent(.leftMouseDown, at: point, in: mounted, modifiers: .option))
        mounted.textView.finishRectangularSelectionGesture(atViewPoint: point)

        #expect(mounted.system.selectionSet.isMultiple)
        #expect(mounted.system.selectionSet.ranges.contains(NSRange(location: 8, length: 0)))
        #expect(mounted.system.selectionSet.ranges.contains(NSRange(location: 0, length: 0)))
    }

    @Test func subThresholdJitterDuringAnOptionClickDoesNotEngageRectangularMode() throws {
        let mounted = try mount(text: "one two three")
        mounted.system.selectedRange = NSRange(location: 0, length: 0)
        let point = try viewPoint(at: 8, in: mounted)
        let jitter = CGPoint(x: point.x + 1, y: point.y) // well under the 4pt threshold

        try mounted.textView.mouseDown(with: syntheticEvent(.leftMouseDown, at: point, in: mounted, modifiers: .option))
        try mounted.textView.mouseDragged(with: syntheticEvent(
            .leftMouseDragged,
            at: jitter,
            in: mounted,
            modifiers: .option
        ))
        mounted.textView.finishRectangularSelectionGesture(atViewPoint: jitter)

        // Still just the toggle's own two carets -- no third range from an
        // accidental one-line "rectangle."
        #expect(mounted.system.selectionSet.count == 2)
    }

    // A "plain (non-Option) drag falls through to native handling
    // unchanged" case is deliberately NOT exercised via a real
    // `mouseDown(with:)` call here, for the exact same already-documented
    // reason `EditorOptionClickTests` doesn't: `Self.isPlainOptionClick`
    // being false sends this method straight to `super.mouseDown(with:)`,
    // whose real implementation hangs a headless test past its timeout
    // against one isolated synthetic event. `mouseDown(with:)`'s own
    // `guard`-then-fall-through structure is simple enough that reading it
    // is adequate; forcing this specific path through in a test is not
    // worth the risk of a hanging suite.

    private func syntheticEvent(
        _ type: NSEvent.EventType,
        at viewPoint: CGPoint,
        in mounted: Mounted,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        let windowPoint = mounted.textView.convert(viewPoint, to: nil)
        return try #require(NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: mounted.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
