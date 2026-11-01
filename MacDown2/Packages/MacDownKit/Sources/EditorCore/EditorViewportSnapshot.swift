import AppKit

/// The editor state preserved across a clean external replacement.
///
/// Both the selected range and all editor range APIs are UTF-16 based.
public struct EditorViewportSnapshot: Equatable {
    public let selectedRange: NSRange
    public let scrollOffset: CGFloat
    /// The source location at the top of the viewport when it was captured.
    /// A disk replacement can change TextKit's frame metrics before a raw
    /// offset is safe to restore, while this location remains meaningful.
    public let topVisibleUTF16Offset: Int?
    /// Vertical distance from that fragment's top to the clip origin. A
    /// wrapped source line can span several visible rows; preserving only
    /// its source location would snap the reader to its first row.
    public let topVisibleFragmentOffset: CGFloat?

    public init(
        selectedRange: NSRange,
        scrollOffset: CGFloat,
        topVisibleUTF16Offset: Int? = nil,
        topVisibleFragmentOffset: CGFloat? = nil
    ) {
        self.selectedRange = selectedRange
        self.scrollOffset = scrollOffset
        self.topVisibleUTF16Offset = topVisibleUTF16Offset
        self.topVisibleFragmentOffset = topVisibleFragmentOffset
    }
}
