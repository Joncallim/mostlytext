import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
struct TabStoreDocumentFilePublicationTests {
    @Test func inactiveInsertionNotifiesBeforePublicationWhileTextEditsDoNot() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab(document: FileDocument(text: "first"))
        let active = store.activeTabID
        let incoming = WorkspaceTab(document: FileDocument(fileURL: URL(fileURLWithPath: "/tmp/later.md")))
        var calls = 0
        store.setDocumentFilesWillPublish { newTabs in
            calls += 1
            #expect(store.tabs.count == 1)
            #expect(newTabs.count == 2)
            #expect(newTabs.last?.id == incoming.id)
            #expect(store.activeTabID == active)
        }
        store.updateActiveDocument { $0.updatingText("edited") }
        #expect(calls == 0)
        store.tabs.append(incoming)
        #expect(calls == 1)
        #expect(store.activeTabID == active)
    }

    @Test func changedURLNotifiesBeforeTheOldNameDisappears() {
        let store = TabStore(sessionStore: FakeSessionStore())
        let old = URL(fileURLWithPath: "/tmp/original.md")
        let new = URL(fileURLWithPath: "/tmp/replaced.md")
        store.newTab(document: FileDocument(fileURL: old))
        var calls = 0
        store.setDocumentFilesWillPublish { incoming in
            calls += 1
            #expect(store.activeDocument?.fileURL == old)
            #expect(incoming.first?.document.fileURL == new)
        }
        store.updateActiveDocument { _ in FileDocument(fileURL: new) }
        #expect(calls == 1)
    }

    @Test func aChangedPhysicalObjectAtTheSameURLNotifiesBeforePublication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tab-backing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.md")
        try Data("original".utf8).write(to: url)
        let original = try FileDocument(fileURL: url).load()
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab(document: original)
        try Data("replacement".utf8).write(to: url, options: .atomic)
        let replacement = try FileDocument(fileURL: url).load()
        #expect(original.lastKnownRevision?.fileObjectID != replacement.lastKnownRevision?.fileObjectID)
        var calls = 0
        store.setDocumentFilesWillPublish { incoming in
            calls += 1
            #expect(store.activeDocument?.lastKnownRevision == original.lastKnownRevision)
            #expect(incoming.first?.document.lastKnownRevision == replacement.lastKnownRevision)
        }
        store.updateActiveDocument { _ in replacement }
        #expect(calls == 1)
    }
}
