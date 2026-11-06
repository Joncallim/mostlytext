import AppKit

/// Paint only the primary logical line's visible geometry, behind native text
/// and selection, without laying out a distant caret or walking wrapped rows.
extension EditorTextView {
    @discardableResult
    func drawCurrentLineBackground(in dirtyRect: NSRect) -> Int {
        let visible = dirtyRect.intersection(visibleRect)
        guard currentLineColor.alphaComponent > 0, let system = owningSystem,
              let textLayoutManager, !visible.isEmpty else { return 0 }
        let activeLine = system.currentLogicalLine
        let inset = textContainerInset
        let containerTop = CGPoint(x: visible.minX - inset.width, y: visible.minY - inset.height)
        let first = textLayoutManager.textLayoutFragment(for: containerTop)?.rangeInElement.location
        guard first != nil || system.lineIndex.utf16Length == 0 else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        currentLineColor.setFill()
        var visited = 0
        textLayoutManager.enumerateTextLayoutFragments(
            from: first ?? textLayoutManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            visited += 1
            let frame = fragment.layoutFragmentFrame
            guard frame.minY < visible.maxY - inset.height else { return false }
            guard frame.maxY > visible.minY - inset.height else { return true }
            let offset = textLayoutManager.offset(from: textLayoutManager.documentRange.location,
                                                  to: fragment.rangeInElement.location)
            fillCurrentLine(fragment: fragment, offset: offset, activeLine: activeLine,
                            system: system, viewport: (visible, inset.height))
            return true
        }
        return visited
    }

    private func fillCurrentLine(fragment: NSTextLayoutFragment, offset: Int, activeLine: Int,
                                 system: EditorTextSystem, viewport: (visible: NSRect, insetTop: CGFloat)) {
        let (visible, insetTop) = viewport
        let frame = fragment.layoutFragmentFrame
        let extra = system.trailingEmptyLine(in: fragment, startingAt: offset)
        if system.lineIndex.line(atUTF16Offset: offset) == activeLine {
            fillBand(top: frame.minY + insetTop, height: extra?.typographicBounds.minY ?? frame.height,
                     visible: visible)
        }
        if activeLine == system.lineIndex.lineCount, let extra {
            fillBand(top: frame.minY + extra.typographicBounds.minY + insetTop,
                     height: extra.typographicBounds.height, visible: visible)
        }
    }

    private func fillBand(top: CGFloat, height: CGFloat, visible: NSRect) {
        let band = NSRect(x: visible.minX, y: top, width: visible.width, height: max(0, height)).intersection(visible)
        if !band.isEmpty {
            NSBezierPath(rect: band).fill()
        }
    }
}
