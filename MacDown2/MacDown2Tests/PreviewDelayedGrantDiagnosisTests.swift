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

    @Test func aBaselineReceivedAfterBackingAcquisitionCannotStrandTheGrantedImage() async throws {
        let label = "controlled-baseline-" + UUID().uuidString
        let source = "![\(label)](image.png)\n"
        let fixture = try PreviewProductionFixture(source: source, previewLayout: .split(fraction: 0.5))
        defer { fixture.dispose() }
        fixture.first.externalFileController.dispose()
        let pasteboard = fixture.copyHarness.snapshotPasteboard()
        defer { fixture.copyHarness.restorePasteboard(pasteboard) }
        let initial = try #require(fixture.first.model.activeDocument)
        try #require(initial.lastKnownRevision == nil)
        let url = try #require(initial.fileURL)
        let snapshot = try await Task.detached { try FileStore().readSnapshot(from: url) }.value
        try #require(snapshot.text.utf8.elementsEqual(source.utf8))
        let root = try await observeDeniedSource(label, in: fixture)
        let owner = fixture.first.previewResourceState
        let origin = try #require(owner.beginSelection(for: initial))
        let receipt = try fixture.selection()
        var resolutions = 0
        var metadataAdvanced = false
        try await owner.install(receipt, from: origin) {
            resolutions += 1
            if resolutions == 2 {
                fixture.first.model.tabStore.updateActiveDocument { document in
                    let next = document.reconcilingExternalSnapshot(snapshot).document
                    metadataAdvanced = next.mutationGeneration > document.mutationGeneration
                    return next
                }
            }
            return fixture.first.model.activeDocument
        }
        let current = try #require(fixture.first.model.activeDocument)
        try #require(metadataAdvanced)
        #expect(current.id == initial.id && current.recoveryEpoch == initial.recoveryEpoch)
        #expect(current.mutationGeneration == initial.mutationGeneration + 1)
        #expect(current.lastKnownRevision == snapshot.revision)
        #expect(current.text.utf8.elementsEqual(source.utf8))
        #expect(owner.hasGrant(for: current))
        print("CONTROLLED_BASELINE_GRANT initial=\(initial.mutationGeneration) current=\(current.mutationGeneration)")
        try await fixture.copyHarness.assertGrantedImageCopies(from: root) {
            #if DEBUG || RELEASE_PREVIEW_PROBE
                PreviewResourceDiagnostics.dump("production-controlled-baseline-copy-failure")
            #endif
            return "Actual disk baseline delivered between pinned backing acquisition and grant publication"
        }
    }

    private func observeDeniedSource(_ label: String, in fixture: PreviewProductionFixture) async throws -> NSView {
        let root = try fixture.root()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var html = ""
        while ContinuousClock.now < deadline {
            html = try await fixture.copyHarness.copiedHTML(from: root)
            if html.contains(label) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(html.contains(label))
        try #require(!html.contains("data:image/png;base64,"))
        try #require(fixture.first.model.activeDocument?.lastKnownRevision == nil)
        return root
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
