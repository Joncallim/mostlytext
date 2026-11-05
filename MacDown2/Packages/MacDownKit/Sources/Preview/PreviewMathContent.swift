import Foundation
import Textual

/// The app prepares one immutable source-bound native snapshot. Preview owns
/// its presentation without importing the math evaluation/rendering module.
public struct PreviewMathContent: Sendable {
    public enum Block: Sendable {
        case parsed(PreviewMathInput)
        case literal
    }

    public let id: UUID
    public let blocks: [UUID: Block]
    public let attachments: [UUID: AnyAttachment]

    public init(id: UUID = UUID(), blocks: [UUID: Block], attachments: [UUID: AnyAttachment] = [:]) {
        self.id = id
        self.blocks = blocks
        self.attachments = attachments
    }
}
