import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("Preview document identity publication")
struct TabStorePreviewIdentityBoundaryTests {
    @Test func documentReplacementNotifiesBeforePublicationButTextEditDoesNot() {
        let store = TabStore(sessionStore: FakeSessionStore())
        let first = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/first.md"), text: "first")
        store.newTab(document: first)
        let firstRevision = store.activeIdentityRevision
        var oldIDs: [String?] = []
        var newIDs: [String?] = []
        store.setActiveIdentityWillChange { old, new in
            #expect(store.activeDocument?.id == old?.documentID)
            #expect(store.activeDocument?.fileURL == old?.fileURL)
            oldIDs.append(old?.documentID)
            newIDs.append(new?.documentID)
        }

        store.updateActiveDocument { $0.updatingText("edited") }
        #expect(oldIDs.isEmpty)
        #expect(store.activeIdentityRevision == firstRevision)

        let second = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/second.md"), text: "second")
        store.updateActiveDocument { _ in second }
        #expect(oldIDs == [first.id])
        #expect(newIDs == [second.id])
        #expect(store.activeDocument?.id == second.id)
        #expect(store.activeIdentityRevision == firstRevision + 1)
    }

    @Test func sameDocumentInDifferentTabStillInvalidatesBeforeActivation() throws {
        let store = TabStore(sessionStore: FakeSessionStore())
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/same.md"), text: "same")
        store.newTab(document: document)
        let firstTab = try #require(store.activeTabID)
        var changes: [(ActiveDocumentIdentity?, ActiveDocumentIdentity?)] = []
        store.setActiveIdentityWillChange { old, new in
            changes.append((old, new))
        }

        store.newTab(document: document)
        let secondTab = try #require(store.activeTabID)
        let afterSwitch = store.activeIdentityRevision
        #expect(changes.count == 1)
        #expect(changes[0].0?.tabID == firstTab)
        #expect(changes[0].1?.tabID == secondTab)
        #expect(changes[0].0?.documentID == changes[0].1?.documentID)

        changes.removeAll()
        store.activate(firstTab)
        #expect(store.activeIdentityRevision == afterSwitch + 1)
        #expect(store.activeDocumentIdentity?.tabID == firstTab)
        #expect(changes.count == 1)
        #expect(changes[0].0?.tabID == secondTab)
        #expect(changes[0].1?.tabID == firstTab)
    }

    @Test func directRenameAndDeletionNotifyBeforeOldIdentityDisappears() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        let oldURL = URL(fileURLWithPath: "/tmp/preview-old.md")
        let newURL = URL(fileURLWithPath: "/tmp/preview-new.md")
        store.newTab(document: FileDocument(fileURL: oldURL, text: "saved"))
        var seenOldURLs: [URL?] = []
        var seenNewURLs: [URL?] = []
        store.setActiveIdentityWillChange { old, new in
            #expect(store.activeDocument?.fileURL == old?.fileURL)
            seenOldURLs.append(old?.fileURL)
            seenNewURLs.append(new?.fileURL)
        }

        #expect(await store.documentWasRenamed(from: oldURL, to: newURL))
        #expect(seenOldURLs == [oldURL])
        #expect(seenNewURLs == [newURL])
        #expect(store.documentFileWasDeleted(at: newURL) != .notOpen)
        #expect(seenOldURLs == [oldURL, newURL])
        #expect(seenNewURLs.count == 2)
        #expect(seenNewURLs[1] == nil)
    }
}
