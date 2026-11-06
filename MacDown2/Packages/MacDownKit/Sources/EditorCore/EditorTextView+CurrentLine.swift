import AppKit

/// The current-line wash is drawn by TextKit 2's editor view, behind text and
/// selection. It visits only layout fragments intersecting the visible dirty
/// rectangle; a wrapped source line remains one logical active line.
extension EditorTextView {
    @discardableResult
    func drawCurrentLineBackground(in dirtyRect: NSRect) -> Int {
        let visible = dirtyRect.intersection(visibleRect)
        guard currentLineColor.alphaComponent > 0, let system = owningSystem,
              let textLayoutManager, !visible.isEmpty else { return 0 }

        let activeLine = system.currentLogicalLine
        let inset = textContainerInset
        let containerTop = CGPoint(x: visible.minX - inset.width, y: visible.minY - inset.height)
        guard let first = textLayoutManager.textLayoutFragment(for: containerTop) else { return 0 }
        let maxY = visible.maxY - inset.height
        let minY = visible.minY - inset.height

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        currentLineColor.setFill()
        var visited = 0
        textLayoutManager.enumerateTextLayoutFragments(
            from: first.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            visited += 1
            let frame = fragment.layoutFragmentFrame
            guard frame.minY < maxY else { return false }
            guard frame.maxY > minY else { return true }
            let offset = textLayoutManager.offset(
                from: textLayoutManager.documentRange.location,
                to: fragment.rangeInElement.location
            )
            guard system.lineIndex.line(atUTF16Offset: offset) == activeLine else { return true }
            let band = NSRect(
                x: visible.minX,
                y: frame.minY + inset.height,
                width: visible.width,
                height: frame.height
            ).intersection(visible)
            if !band.isEmpty {
                NSBezierPath(rect: band).fill()
            }
            return true
        }
        return visited
    }
}
