import AppKit
import CoreText

/// Line-number gutter for the editor's `NSScrollView`, backed by
/// `EditorTextSystem.lineIndex` and `enumerateVisibleLineFragments(_:)`.
/// Draws only the currently visible, already-laid-out lines — never walks
/// the whole document — per epic-22-implementation.md §6.6's
/// viewport-laziness contract. A wrapped logical line's continuation
/// fragments are skipped by `EditorGutterLayout`, so only the fragment
/// that actually starts a logical line gets a number.
@MainActor
public final class EditorGutterView: NSRulerView {
    private weak var system: EditorTextSystem?

    private static let horizontalPadding: CGFloat = 6
    private static let markerWidth: CGFloat = 3
    private static let markerGap: CGFloat = 3
    private static let minimumThickness: CGFloat = 32

    public init(scrollView: NSScrollView, system: EditorTextSystem) {
        self.system = system
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = system.textView
        updateThickness()
        // epic-22-implementation.md §12: new UI ships with basic
        // accessibility labels/identifiers from the same slice that
        // introduces it, not deferred to a later cleanup pass.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Line numbers", bundle: .module))
        setAccessibilityIdentifier("editorGutter")
    }

    @available(*, unavailable)
    public required init(coder _: NSCoder) {
        fatalError("EditorGutterView does not support NSCoder")
    }

    /// Recomputes `ruleThickness` from the document's current digit count
    /// and marks the ruler for redraw. Call after any edit that could grow
    /// or shrink the line count (a 9-to-10-line, or 99-to-100-line, change
    /// needs one more/fewer digit of width) and after font changes.
    public func updateThickness() {
        guard let system else { return }
        let digitCount = String(max(1, system.lineIndex.lineCount)).count
        let font = system.textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let digitWidth = max(Self.widestDigitWidth(in: font), Self.widestDigitWidth(in: Self.activeLineFont(for: font)))
        let needed = digitWidth * CGFloat(digitCount) + Self.horizontalPadding * 2
            + Self.markerWidth + Self.markerGap
        let newThickness = max(Self.minimumThickness, needed.rounded(.up))
        guard newThickness != ruleThickness else {
            needsDisplay = true
            return
        }
        ruleThickness = newThickness
        needsDisplay = true
    }

    /// The widest "0"..."9" glyph in `font`. The editor's font picker offers
    /// every installed font family via `NSFontManager.availableFontFamilies`
    /// (`DocumentEditorSplitView+AppSettings.swift`), not just monospace
    /// ones, so a proportional or display font could render some other
    /// digit wider than "0" — measuring only "0" risks clipping labels'
    /// left edge once the line count needs that wider digit.
    private static func widestDigitWidth(in font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return "0123456789".reduce(CGFloat(0)) { widest, digit in
            max(widest, (String(digit) as NSString).size(withAttributes: attributes).width)
        }
    }

    /// Weight, as well as color, identifies the primary caret's logical line.
    /// A font without a bold face falls back to a system bold face so the cue
    /// never depends solely on the theme color.
    static func activeLineFont(for font: NSFont) -> NSFont {
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        return bold.fontDescriptor.symbolicTraits.contains(.bold)
            ? bold : NSFont.boldSystemFont(ofSize: font.pointSize)
    }

    /// Core Text uses y-up glyph coordinates even when AppKit gives a view a
    /// flipped drawing context. Keep this small policy separate so the
    /// rendering regression can verify the exact orientation contract.
    static func coreTextMatrix(forFlippedView isFlipped: Bool) -> CGAffineTransform {
        isFlipped ? CGAffineTransform(scaleX: 1, y: -1) : .identity
    }

    override public func drawHashMarksAndLabels(in dirtyRect: NSRect) {
        guard let system, let cgContext = NSGraphicsContext.current?.cgContext else { return }
        let font = system.textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let editor = system.textView as? EditorTextView
        let textColor = editor?.gutterForegroundColor ?? system.textView.textColor?.withAlphaComponent(0.5)
            ?? .secondaryLabelColor
        let activeColor = editor?.gutterForegroundColor ?? system.textView.textColor ?? .labelColor
        let callerTextMatrix = cgContext.textMatrix
        cgContext.saveGState()
        defer {
            cgContext.restoreGState()
            cgContext.textMatrix = callerTextMatrix
        }
        cgContext.clip(to: bounds.intersection(dirtyRect))
        (editor?.gutterBackgroundColor ?? system.textView.backgroundColor).setFill()
        bounds.fill()

        var fragments: [(utf16Offset: Int, baselineY: CGFloat)] = []
        system.enumerateVisibleLineFragments { offset, baselineY in
            fragments.append((offset, baselineY))
        }
        let labels = EditorGutterLayout.labels(for: fragments, lineIndex: system.lineIndex)

        let activeLine = system.currentLogicalLine
        let activeFont = Self.activeLineFont(for: font)
        let insetTop = system.textView.textContainerInset.height

        // Core Text's default text matrix assumes a y-up coordinate system.
        // A mounted ruler follows the editor's flipped coordinates, so
        // normalize only Core Text's glyph orientation -- not the context's
        // CTM or the already-correct TextKit baseline below.  Scope this so
        // nothing about the caller's drawing state leaks out of the gutter.
        // `textMatrix` is not included in CGContext's saved graphics state,
        // and CTLineDraw advances it to the final glyph position. Preserve it
        // explicitly as well as the ordinary graphics state.
        cgContext.textMatrix = Self.coreTextMatrix(forFlippedView: isFlipped)

        for label in labels {
            let string = String(label.lineNumber)
            let isActive = label.lineNumber == activeLine
            let attributes: [NSAttributedString.Key: Any] = [
                .font: isActive ? activeFont : font,
                .foregroundColor: isActive ? activeColor : textColor,
            ]
            // Drawn via CoreText's own baseline-relative `textPosition`,
            // not `NSString.draw(in:withAttributes:)` -- see
            // `EditorTextSystem.enumerateVisibleLineFragments`'s own doc
            // comment for why: this editor's `lineHeightMultiple` (default
            // 1.2) makes each real text row TALLER than its font's natural
            // line height and pushes the glyphs' baseline down within that
            // taller box by an amount `NSStringDrawing`'s own
            // positioning-within-a-rect has no way to reproduce (it knows
            // nothing about `label.baselineY`, which is TextKit's own
            // already-computed real answer). `textPosition` sidesteps that
            // ambiguity entirely: it is CoreText's literal, unambiguous "the
            // NEXT glyph run's baseline goes exactly here" contract.
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let baselinePoint = convert(NSPoint(x: 0, y: label.baselineY + insetTop), from: system.textView)
            if isActive {
                activeColor.setFill()
                let marker = NSRect(
                    x: bounds.width - width - Self.horizontalPadding - Self.markerGap - Self.markerWidth,
                    y: baselinePoint.y - activeFont.ascender,
                    width: Self.markerWidth,
                    height: activeFont.ascender - activeFont.descender
                )
                NSBezierPath(roundedRect: marker, xRadius: 1, yRadius: 1).fill()
            }
            cgContext.textPosition = CGPoint(x: bounds.width - width - Self.horizontalPadding, y: baselinePoint.y)
            CTLineDraw(ctLine, cgContext)
        }
    }
}
