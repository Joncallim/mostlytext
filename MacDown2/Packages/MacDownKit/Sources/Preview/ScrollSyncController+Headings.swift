import Foundation

public struct PreviewHeadingScrollTarget {
    public let block: PreviewBlockTarget
    public let animated: Bool
}

public extension ScrollSyncController {
    internal struct PendingHeadingJump {
        let line: Int
        let animated: Bool
        let validate: @MainActor @Sendable () -> Bool
    }

    /// The host captures only weak live owners. Unlike ordinary scroll-sync
    /// fractions, a heading action retains a source guard until consumption.
    func queueHeadingJump(
        toLine line: Int, animated: Bool, validate: @escaping @MainActor @Sendable () -> Bool
    ) {
        targetPreviewFraction = nil
        targetPreviewBlock = nil
        animatesNextPreviewScroll = false
        pendingHeadingJump = .init(line: line, animated: animated, validate: validate)
        headingJumpID = UUID()
    }

    func consumeHeadingJump() -> PreviewHeadingScrollTarget? {
        let pending = pendingHeadingJump
        pendingHeadingJump = nil
        headingJumpID = nil
        guard let pending, pending.validate(), let block = blockTarget(forLine: pending.line) else { return nil }
        jumpSettleDeadline = now() + Self.jumpSettleWindow
        lastPreviewDrivenBlockIndex = nil
        lastEditorDrivenBlockIndex = block.blockIndex
        recordRequest(block.blockIndex, into: &recentEditorRequestedBlocks)
        return PreviewHeadingScrollTarget(block: block, animated: pending.animated)
    }
}
