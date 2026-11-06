import Foundation

/// Primitives only: the live provider must obtain these values again from the
/// registered window, active model/editor and existing parser after every await.
struct PreviewSourceStamp: Sendable, Hashable {
    var tabIdentity: String
    var documentID: String
    var recoveryEpoch: UUID
    var mutationGeneration: UInt
    var parseIdentity: UUID
    var parsedRevision: Int
    var sourceSHA256: String
}

struct PreviewLiveSource: Sendable {
    var stamp: PreviewSourceStamp
    var modelText: String
    var editorText: String
    var publishedText: String
    var isKeyWindow: Bool
}

/// One immutable request owns its source. A matching digest or equal-looking
/// Unicode text is insufficient for either publication or source navigation.
struct PreviewSourceBinding: Sendable {
    let id = UUID()
    let stamp: PreviewSourceStamp
    let source: String

    func isCurrent(_ live: PreviewLiveSource?) -> Bool {
        guard let live, live.stamp == stamp else { return false }
        return live.modelText.utf8.elementsEqual(source.utf8) &&
            live.editorText.utf8.elementsEqual(source.utf8) &&
            live.publishedText.utf8.elementsEqual(source.utf8)
    }

    /// A delayed native action must belong to the current prepared layout as
    /// well as the current source, even when a later snapshot reused an ID.
    func allowsNavigation(frameID: UUID, currentFrameID: UUID, live: PreviewLiveSource?) -> Bool {
        frameID == currentFrameID && live?.isKeyWindow == true && isCurrent(live)
    }
}

struct MathPreviewSourceAction: Sendable {
    let frameID: UUID
    let sourceID: UUID
    let diagnostic: Bool
}

// Preserve existing math callers while both derived-content features share
// exactly the same live source and lifetime checks.
typealias MathPreviewSourceStamp = PreviewSourceStamp
typealias MathPreviewLiveSource = PreviewLiveSource
typealias MathPreviewSourceBinding = PreviewSourceBinding
