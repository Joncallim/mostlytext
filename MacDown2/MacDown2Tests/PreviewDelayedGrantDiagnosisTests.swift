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
        let initial = try #require(fixture.first.model.activeDocument)
        try #require(!fixture.first.previewResourceState.hasGrant(for: initial))
        observeFileBinding(fixture)
        defer { fixture.first.externalFileController.afterObservationContextHandled = nil }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        try await waitForInitialBinding(fixture, before: deadline)
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
        let original = try #require(fixture.first.model.activeDocument)
        try #require(original.id == initial.id && original.recoveryEpoch == initial.recoveryEpoch)
        try #require(original.text.utf8.elementsEqual(source.utf8))
        try #require(!fixture.first.previewResourceState.hasGrant(for: original))
        print("DELAYED_GRANT_OBSERVATION initial=\(initial.mutationGeneration) denied=\(original.mutationGeneration)")
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
        print("DELAYED_GRANT_OBSERVATION granted=\(current.mutationGeneration)")
        #expect(current.text.utf8.elementsEqual(source.utf8))
        #expect(fixture.first.previewResourceState.hasGrant(for: current))
        try await fixture.copyHarness.assertGrantedImageCopies(from: root) {
            #if DEBUG || RELEASE_PREVIEW_PROBE
                PreviewResourceDiagnostics.dump("production-delayed-grant-copy-failure")
            #endif
            return "The same observed ungranted document now has its original window's explicit folder grant"
        }
    }

    private func observeFileBinding(_ fixture: PreviewProductionFixture) {
        fixture.first.externalFileController.afterObservationContextHandled = { _ in
            let current = fixture.first.model.activeDocument
            print("DELAYED_GRANT_BINDING generation=\(current?.mutationGeneration ?? 0) "
                + "baseline=\(current?.lastKnownRevision != nil)")
        }
    }

    private func waitForInitialBinding(
        _ fixture: PreviewProductionFixture, before deadline: ContinuousClock.Instant
    ) async throws {
        while fixture.first.model.activeDocument?.lastKnownRevision == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(fixture.first.model.activeDocument?.lastKnownRevision != nil)
    }
}
