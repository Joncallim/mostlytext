import Foundation
@testable import MacDown2
import Testing

struct MathPreviewSourceBindingTests {
    private func stamp() -> MathPreviewSourceStamp {
        .init(tabIdentity: UUID().uuidString, documentID: "file:///tmp/owned.md", recoveryEpoch: UUID(),
              mutationGeneration: 7, parseIdentity: UUID(), parsedRevision: 4, sourceSHA256: "frozen-source-digest")
    }

    private func live(_ stamp: MathPreviewSourceStamp, source: String = "$x$") -> MathPreviewLiveSource {
        .init(stamp: stamp, modelText: source, editorText: source, publishedText: source, isKeyWindow: true)
    }

    @Test func onlyTheCurrentOwnedWindowCanNavigateWhileBackgroundAnalysisMayPublish() {
        let stamp = stamp()
        let binding = MathPreviewSourceBinding(stamp: stamp, source: "$x$")
        let frame = UUID()
        var current = live(stamp)
        #expect(binding.isCurrent(current))
        #expect(binding.allowsNavigation(frameID: frame, currentFrameID: frame, live: current))
        current.isKeyWindow = false
        #expect(binding.isCurrent(current))
        #expect(!binding.allowsNavigation(frameID: frame, currentFrameID: frame, live: current))
        #expect(!binding.isCurrent(nil))
        #expect(!binding.allowsNavigation(frameID: frame, currentFrameID: frame, live: nil))
    }

    @Test func closingAndReopeningTheSamePathCannotReuseOldSourceAuthority() {
        let stamp = stamp()
        let binding = MathPreviewSourceBinding(stamp: stamp, source: "$x$")
        var reopened = live(stamp)
        reopened.stamp.recoveryEpoch = UUID()
        #expect(!binding.isCurrent(reopened))
        reopened = live(stamp)
        reopened.stamp.tabIdentity = UUID().uuidString
        #expect(!binding.isCurrent(reopened))
        reopened = live(stamp)
        reopened.stamp.documentID = "file:///tmp/save-as.md"
        #expect(!binding.isCurrent(reopened))
    }

    @Test func aNontextSaveRequiresFreshBindingAndCanThenPublishTheSameSource() {
        let original = stamp()
        let binding = MathPreviewSourceBinding(stamp: original, source: "$x$")
        var saved = original
        saved.mutationGeneration += 1
        let current = live(saved)
        #expect(!binding.isCurrent(current))
        let refreshed = MathPreviewSourceBinding(stamp: saved, source: "$x$")
        #expect(refreshed.isCurrent(current))
        #expect(refreshed.id != binding.id)
    }

    @Test func parserReplacementAndSettingsReparseInvalidateOldCompletion() {
        let original = stamp()
        let binding = MathPreviewSourceBinding(stamp: original, source: "$x$")
        var current = live(original)
        current.stamp.parseIdentity = UUID()
        #expect(!binding.isCurrent(current))
        current = live(original)
        current.stamp.parsedRevision += 1
        #expect(!binding.isCurrent(current))
        current = live(original)
        current.stamp.sourceSHA256 = "other-source-digest"
        #expect(!binding.isCurrent(current))
    }

    @Test(arguments: [("\u{0340}", "\u{0300}"), ("é", "e\u{301}")])
    func canonicalLookalikesAndAnUnchangedDigestCannotAuthorizeDifferentEditorBytes(_ pair: (String, String)) {
        #expect(pair.0 == pair.1)
        #expect(!pair.0.utf8.elementsEqual(pair.1.utf8))
        let stamp = stamp()
        let binding = MathPreviewSourceBinding(stamp: stamp, source: pair.0)
        var current = live(stamp, source: pair.0)
        #expect(binding.isCurrent(current))
        current.modelText = pair.1
        #expect(!binding.isCurrent(current))
        current = live(stamp, source: pair.0)
        current.editorText = pair.1
        #expect(!binding.isCurrent(current))
        current = live(stamp, source: pair.0)
        current.publishedText = pair.1
        #expect(!binding.isCurrent(current))
    }

    @Test func anOldNativeFrameCannotActAfterARefreshWithUnchangedSource() {
        let stamp = stamp()
        let binding = MathPreviewSourceBinding(stamp: stamp, source: "$x$")
        let oldFrame = UUID(), currentFrame = UUID()
        let current = live(stamp)
        #expect(binding.isCurrent(current))
        #expect(!binding.allowsNavigation(frameID: oldFrame, currentFrameID: currentFrame, live: current))
        #expect(binding.allowsNavigation(frameID: currentFrame, currentFrameID: currentFrame, live: current))
    }
}
