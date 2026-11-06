import AppKit

extension EditorTextSystem {
    /// TextKit may store the final empty visual row inside the preceding
    /// paragraph. Only the actual final logical empty line owns that row.
    func trailingEmptyLine(in fragment: NSTextLayoutFragment, startingAt offset: Int) -> NSTextLineFragment? {
        let length = lineIndex.utf16Length
        guard lineIndex.lineStartOffsets.last == length, (0 ... length).contains(offset),
              let row = fragment.textLineFragments.last, row.characterRange.length == 0,
              row.characterRange.location == length - offset else { return nil }
        return row
    }
}
