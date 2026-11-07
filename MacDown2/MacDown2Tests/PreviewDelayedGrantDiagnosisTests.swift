import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing

/// Separate from the original startup-race selection: observing this transition cannot waive that failure.
@MainActor
@Suite("Production Preview delayed grant diagnosis", .serialized)
struct PreviewDelayedGrantDiagnosisTests {
    @Test func anObservedDeniedImageCanLoadAfterTheSameDocumentReceivesItsGrant() async throws {
        let label = "delayed-grant-" + UUID().uuidString
        let source = "![\(label)](image.png)\n"
        let fixture = try PreviewProductionFixture(source: source, previewLayout: .split(fraction: 0.5))
        defer { fixture.dispose() }
        let previous = fixture.copyHarness.snapshotPasteboard()
        defer { fixture.copyHarness.restorePasteboard(previous) }
        let root = try fixture.root()
        let original = try #require(fixture.first.model.activeDocument)
        try #require(!fixture.first.previewResourceState.hasGrant(for: original))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var deniedHTML = ""
        while ContinuousClock.now < deadline {
            deniedHTML = try await fixture.copyHarness.copiedHTML(from: root)
            if deniedHTML.contains(label) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(deniedHTML.contains(label), "The actual current document must expose its unique ungranted image")
        #expect(!deniedHTML.contains("data:image/png;base64,"))
        let receipt = try fixture.selection()
        let task = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { window, url in
            #expect(window === fixture.first.window)
            #expect(url == receipt.requestedDocumentURL)
            return receipt
        })
        try #require(await task.value)
        let current = try #require(fixture.first.model.activeDocument)
        #expect(current.id == original.id)
        #expect(current.recoveryEpoch == original.recoveryEpoch)
        #expect(current.mutationGeneration == original.mutationGeneration)
        #expect(current.text.utf8.elementsEqual(source.utf8))
        #expect(fixture.first.previewResourceState.hasGrant(for: current))
        try await fixture.copyHarness.assertGrantedImageCopies(from: root) {
            #if DEBUG || RELEASE_PREVIEW_PROBE
                PreviewResourceDiagnostics.dump("production-delayed-grant-copy-failure")
            #endif
            return "The same observed ungranted document now has its original window's explicit folder grant"
        }
    }
}
