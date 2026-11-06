import AppKit

public extension EditorTextSystem {
    /// The primary selection is the visual current line even when an earlier
    /// secondary selection is the first range reported by AppKit.
    var currentLogicalLine: Int {
        lineIndex.line(atUTF16Offset: selectionSet.primaryRange.location)
    }

    internal func invalidateCurrentLinePresentation() {
        textView.setNeedsDisplay(textView.visibleRect)
        textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    /// Enumerates `(utf16Offset, baselineY)` for every `NSTextLayoutFragment`
    /// currently materialized in the visible viewport, in top-to-bottom
    /// order, calling `body` for each. Never asks TextKit 2 to lay out
    /// anything beyond the visible rect — mirrors `topVisibleUTF16Offset`'s
    /// existing bounded-lookup discipline and the `<500`-fragments-for-a-
    /// 10 MB-document budget `EditorPerformanceTests.open10MBLazy` pins.
    /// Powers the line-number gutter; a naive whole-document walk of
    /// `lineIndex.lineStartOffsets` to place `lineCount` labels would
    /// violate that same discipline for a large file.
    ///
    /// `baselineY` is the REAL, TextKit-computed baseline of the fragment's
    /// own first visual row (`layoutFragmentFrame.minY` + that row's own
    /// `typographicBounds.minY` + its `glyphOrigin.y`) — not merely the
    /// fragment's top edge. This matters because this editor applies a
    /// `lineHeightMultiple` (`EditorConfiguration.lineHeightMultiple`,
    /// default 1.2) as a base typing attribute (`EditorTextSystem.apply(_:)`),
    /// which makes each line's fragment TALLER than the font's own natural
    /// line height and pushes its glyphs' baseline down within that taller
    /// box by an amount that depends on the font/multiple, not a fixed
    /// constant — a caller that drew a label using only the fragment's own
    /// top edge (ignoring this) would draw it measurably higher than the
    /// real text's baseline. `glyphOrigin`/`typographicBounds` are pure
    /// font+paragraph-style metrics (verified empirically: identical across
    /// every line in a document, including an EMPTY line's own zero-glyph
    /// fragment, which still reports the same `glyphOrigin.y` as a
    /// non-empty one), never content-dependent, so this generalizes to any
    /// font, size, theme, or zoom level without a hand-tuned offset.
    func enumerateVisibleLineFragments(_ body: (_ utf16Offset: Int, _ baselineY: CGFloat) -> Void) {
        guard let scrollView else { return }
        let visibleRect = scrollView.contentView.bounds
        let topPoint = textView.convert(visibleRect.origin, from: scrollView.contentView)
        let bottomPoint = textView.convert(
            NSPoint(x: visibleRect.origin.x, y: visibleRect.maxY),
            from: scrollView.contentView
        )
        let start = layoutManager.textLayoutFragment(for: topPoint)?.rangeInElement.location
        guard start != nil || lineIndex.utf16Length == 0 else { return }

        let documentStart = contentStorage.documentRange.location
        layoutManager.enumerateTextLayoutFragments(
            from: start ?? documentStart,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY < bottomPoint.y else { return false }
            // The FIRST visual row of this fragment -- for a wrapped
            // logical line, this is the row the line number must align
            // with (later rows are continuations and never reach this
            // enumeration as their own fragment; see `EditorGutterLayout`'s
            // own doc comment).
            guard let firstLine = fragment.textLineFragments.first else { return true }
            let baselineY = frame.minY + firstLine.typographicBounds.minY + firstLine.glyphOrigin.y
            let offset = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
            body(offset, baselineY)
            if let extra = trailingEmptyLine(in: fragment, startingAt: offset), offset != lineIndex.utf16Length {
                body(lineIndex.utf16Length, frame.minY + extra.typographicBounds.minY + extra.glyphOrigin.y)
            }
            return true
        }
    }
}
