import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Testing

@MainActor
@Suite("Preview folder selection commands", .serialized)
struct PreviewFolderSelectionCommandTests {
    @Test func originIsReservedBeforeTheCommandTaskCanRun() async throws {
        let fixture = try PreviewProductionFixture(source: "source")
        defer { fixture.dispose() }
        var entered = false
        let pending = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            entered = true
            return try? fixture.selection()
        })
        let replacementURL = fixture.folder.appendingPathComponent("replacement.md")
        try Data("source".utf8).write(to: replacementURL)
        fixture.first.model.tabStore.updateActiveDocument { _ in FileDocument(fileURL: replacementURL, text: "source") }
        #expect(await pending.value == false)
        #expect(!entered, "A stale reserved origin must not open a panel for the replacement")
        let document = try #require(fixture.first.model.activeDocument)
        #expect(!fixture.first.previewResourceState.hasGrant(for: document))
        let fresh = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            try? fixture.selection()
        })
        #expect(await fresh.value)
        #expect(fixture.first.previewResourceState.hasGrant(for: document))
    }

    @Test func aHeldChoiceRemainsWithItsWindowWhenAnotherWindowBecomesKey() async throws {
        let fixture = try PreviewProductionFixture(source: "first")
        defer { fixture.dispose() }
        let second = try fixture.addDocument("second.md", source: "second")
        let receipt = try fixture.selection()
        let gate = FolderSelectionGate()
        defer { gate.finish(nil) }
        let pending = try #require(fixture.coordinator
            .beginPreviewResourceSelection(from: fixture.first) { window, url in
                #expect(window === fixture.first.window)
                #expect(url == receipt.requestedDocumentURL)
                return await gate.choose()
            })
        try await fixture.wait("The actual origin-bound command did not enter its chooser") { gate.entered }
        second.window?.makeKeyAndOrderFront(nil)
        fixture.coordinator.updateKeyModel()
        gate.finish(receipt)
        #expect(await pending.value)
        let originalDocument = try #require(fixture.first.model.activeDocument)
        let otherDocument = try #require(second.model.activeDocument)
        #expect(fixture.first.previewResourceState.hasGrant(for: originalDocument))
        #expect(!second.previewResourceState.hasGrant(for: otherDocument))
    }

    @Test func sameTextSaveAsRejectsAnOlderHeldFolderChoice() async throws {
        let fixture = try PreviewProductionFixture(source: "unchanged source")
        defer { fixture.dispose() }
        let old = try #require(fixture.first.model.activeDocument)
        let receipt = try fixture.selection()
        let gate = FolderSelectionGate()
        defer { gate.finish(nil) }
        let pending = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            await gate.choose()
        })
        try await fixture.wait("The Save As control did not enter its held chooser") { gate.entered }
        let target = fixture.folder.appendingPathComponent("saved-as.md")
        await fixture.first.model.saveAs(to: target, expecting: old)
        let current = try #require(fixture.first.model.activeDocument)
        #expect(current.fileURL == target)
        #expect(current.text.utf8.elementsEqual(old.text.utf8))
        gate.finish(receipt)
        #expect(await pending.value == false)
        #expect(!fixture.first.previewResourceState.hasGrant(for: current))
    }

    @Test func rootAwayAndBackCannotReviveAPendingChoice() async throws {
        let fixture = try PreviewProductionFixture(source: "source")
        defer { fixture.dispose() }
        fixture.first.model.setFolderRoot(fixture.folder)
        let other = fixture.folder.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let receipt = try fixture.selection()
        let gate = FolderSelectionGate()
        defer { gate.finish(nil) }
        let pending = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            await gate.choose()
        })
        try await fixture.wait("The root-switch control did not enter its held chooser") { gate.entered }
        fixture.first.model.setFolderRoot(other)
        fixture.first.model.setFolderRoot(fixture.folder)
        gate.finish(receipt)
        #expect(await pending.value == false)
        let current = try #require(fixture.first.model.activeDocument)
        #expect(!fixture.first.previewResourceState.hasGrant(for: current))
        #expect(!fixture.first.previewResourceState.selectionFailed)
    }

    @Test func anOlderCancellationCannotClearANewerPendingSelection() async throws {
        let fixture = try PreviewProductionFixture(source: "source")
        defer { fixture.dispose() }
        let receipt = try fixture.selection()
        let older = FolderSelectionGate()
        let newer = FolderSelectionGate()
        defer {
            older.finish(nil)
            newer.finish(nil)
        }
        let first = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            await older.choose()
        })
        try await fixture.wait("The older choice did not enter") { older.entered }
        let second = try #require(fixture.coordinator.beginPreviewResourceSelection(from: fixture.first) { _, _ in
            await newer.choose()
        })
        try await fixture.wait("The newer choice did not enter") { newer.entered }
        older.finish(nil)
        #expect(await first.value == false)
        newer.finish(receipt)
        #expect(await second.value, "Finalizing an older choice must not cancel the newer origin")
        let document = try #require(fixture.first.model.activeDocument)
        #expect(fixture.first.previewResourceState.hasGrant(for: document))
    }

    @Test func theRealFolderSheetFinishesWhenItsOriginWindowCloses() async throws {
        let fixture = try PreviewProductionFixture(source: "source")
        defer { fixture.dispose() }
        let window = try #require(fixture.first.window)
        let url = try #require(fixture.first.model.activeDocument?.fileURL)
        let provider = NSFilePanelProvider(window: window)
        var panel: NSOpenPanel?
        var observedParent = false
        var finished = false
        var selected: PreviewResourceFolderSelection?
        let request = Task { @MainActor in
            selected = await provider.choosePreviewResourceFolder(near: url) { presented in
                panel = presented
                observedParent = presented.sheetParent === window
                window.close()
            }
            finished = true
        }
        defer {
            panel?.cancel(nil)
            request.cancel()
        }
        try await fixture.wait("Closing the origin did not finish its actual folder sheet") { finished }
        #expect(observedParent, "The real sheet must be attached to the original document window")
        #expect(selected == nil)
        await request.value
    }
}

@MainActor
private final class FolderSelectionGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<PreviewResourceFolderSelection?, Never>?

    func choose() async -> PreviewResourceFolderSelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
        }
    }

    func finish(_ selection: PreviewResourceFolderSelection?) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: selection)
    }
}
