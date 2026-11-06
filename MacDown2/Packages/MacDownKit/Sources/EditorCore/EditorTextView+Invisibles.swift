import AppKit

extension EditorTextView {
    /// Viewport-bounded: starts at the fragment intersecting `dirtyRect`'s
    /// origin and stops as soon as a fragment's frame is entirely below
    /// `dirtyRect`, mirroring `EditorTextSystem+Gutter.swift`'s
    /// `enumerateVisibleLineFragments` and `EditorTextSystem+Scroll.swift`'s
    /// `topVisibleUTF16Offset` — never a whole-document walk.
    ///
    /// `dirtyRect` (from `draw(_:)`) is in the text view's own bounds space,
    /// which includes `textContainerInset` — but `NSTextLayoutManager`'s
    /// fragment geometry (`layoutFragmentFrame`, `textLayoutFragment(for:)`)
    /// is in the text container's own coordinate space, which excludes it.
    /// Converting to container space for the lookup/bounds check, then back
    /// to view space for each marker's final draw position, is required:
    /// getting this wrong makes every lookup silently miss whenever
    /// `textContainerInset` is nonzero — e.g. `scrollsPastEnd`'s
    /// bottom-overscroll padding, which symmetrically inflates
    /// `textContainerInset.height` at the top too, per `NSTextView.textContainerInset`'s
    /// documented top+bottom (and left+right) symmetry. Found by hostile
    /// review of PR #127: invisibles drew correctly for a from-scratch,
    /// `(0, 0)`-origin full-window paint (every previously-shipped test's
    /// only scenario) but silently drew nothing for an ordinary, genuinely
    /// scrolled dirty rect — exactly what AppKit issues on real scrolling
    /// and per-line edit invalidation.
    func drawInvisibles(in dirtyRect: NSRect, layoutManager: NSTextLayoutManager) {
        let inset = textContainerInset
        let containerOrigin = CGPoint(x: dirtyRect.origin.x - inset.width, y: dirtyRect.origin.y - inset.height)
        guard let startFragment = layoutManager.textLayoutFragment(for: containerOrigin) else { return }
        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: invisiblesColor]
        let containerDirtyMinY = dirtyRect.minY - inset.height
        let containerDirtyMaxY = dirtyRect.maxY - inset.height

        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            guard fragmentFrame.minY < containerDirtyMaxY else { return false }
            guard fragmentFrame.maxY > containerDirtyMinY else { return true }

            for lineFragment in fragment.textLineFragments {
                let lineText = lineFragment.attributedString
                    .attributedSubstring(from: lineFragment.characterRange).string
                for marker in EditorInvisiblesLayout.markers(in: lineText) {
                    let characterIndex = lineFragment.characterRange.location + marker.localUTF16Offset
                    let point = lineFragment.locationForCharacter(at: characterIndex)
                    let glyphString = marker.glyph as NSString
                    let size = glyphString.size(withAttributes: attributes)
                    let rect = NSRect(
                        x: fragmentFrame.minX + point.x + inset.width,
                        y: fragmentFrame.minY + lineFragment.typographicBounds.minY + inset.height,
                        width: size.width,
                        height: max(size.height, lineFragment.typographicBounds.height)
                    )
                    glyphString.draw(in: rect, withAttributes: attributes)
                }
            }
            return true
        }
    }
}
