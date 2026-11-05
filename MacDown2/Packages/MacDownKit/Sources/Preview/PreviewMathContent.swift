import Foundation
import Textual

/// The app prepares one immutable source-bound native snapshot. Preview owns
/// its presentation without importing the math evaluation/rendering module.
public struct PreviewMathContent: Sendable {
    /// App opt-in: defer authored URL authority until the shared source plan
    /// arrives, without changing standalone Preview callers or generated blocks.
    public static let pending = Self(id: UUID(), blocks: [:], attachments: [:], isPending: true)

    public enum Block: Sendable {
        case parsed(PreviewMathInput)
        case literal
    }

    public let id: UUID
    public let blocks: [UUID: Block]
    public let attachments: [UUID: AnyAttachment]
    let isPending: Bool

    public init(id: UUID = UUID(), blocks: [UUID: Block], attachments: [UUID: AnyAttachment] = [:]) {
        self.init(id: id, blocks: blocks, attachments: attachments, isPending: false)
    }

    private init(id: UUID, blocks: [UUID: Block], attachments: [UUID: AnyAttachment], isPending: Bool) {
        self.id = id
        self.blocks = blocks
        self.attachments = attachments
        self.isPending = isPending
    }
}
