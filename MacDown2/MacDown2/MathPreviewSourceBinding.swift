import Foundation

/// Primitives only: the live provider must obtain these values again from the
/// registered window, active model/editor and existing parser after every await.
struct MathPreviewSourceStamp: Sendable, Hashable {
    var tabIdentity: String
    var documentID: String
    var recoveryEpoch: UUID
    var mutationGeneration: UInt
    var parseIdentity: UUID
    var parsedRevision: Int
    var sourceSHA256: String
}

struct MathPreviewLiveSource: Sendable {
    var stamp: MathPreviewSourceStamp
    var modelText: String
    var editorText: String
    var publishedText: String
    var isKeyWindow: Bool
}

/// One immutable request owns its source. A matching digest or equal-looking
/// Unicode text is insufficient for either publication or source navigation.
struct MathPreviewSourceBinding: Sendable {
    let id = UUID()
    let stamp: MathPreviewSourceStamp
    let source: String

    func isCurrent(_ live: MathPreviewLiveSource?) -> Bool {
        guard let live, live.stamp == stamp else { return false }
        return live.modelText.utf8.elementsEqual(source.utf8) &&
            live.editorText.utf8.elementsEqual(source.utf8) &&
            live.publishedText.utf8.elementsEqual(source.utf8)
    }

    /// A delayed native action must belong to the current prepared layout as
    /// well as the current source, even when a later snapshot reused an ID.
    func allowsNavigation(frameID: UUID, currentFrameID: UUID, live: MathPreviewLiveSource?) -> Bool {
        frameID == currentFrameID && live?.isKeyWindow == true && isCurrent(live)
    }
}

struct MathPreviewSourceAction: Sendable {
    let frameID: UUID
    let sourceID: UUID
    let diagnostic: Bool
}
