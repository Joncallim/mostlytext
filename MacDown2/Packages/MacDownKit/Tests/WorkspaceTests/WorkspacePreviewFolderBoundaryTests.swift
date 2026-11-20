import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("Preview folder association publication")
struct WorkspacePreviewFolderBoundaryTests {
    @Test func folderSelectionAndRemapNotifyBeforeNewAssociation() {
        let model = WorkspaceModel(tabStore: TabStore(sessionStore: FakeSessionStore()), stateStore: FakeStateStore())
        let first = URL(fileURLWithPath: "/tmp/preview-first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/preview-second", isDirectory: true)
        let third = URL(fileURLWithPath: "/tmp/preview-third", isDirectory: true)
        model.setFolderRoot(first)
        let firstRevision = model.folderAssociationRevision
        var oldRoots: [URL?] = []
        model.setFolderAssociationWillChange {
            oldRoots.append(model.folderURL)
        }

        model.setFolderRoot(first)
        #expect(oldRoots.isEmpty)
        #expect(model.folderAssociationRevision == firstRevision)
        model.setFolderRoot(second)
        #expect(oldRoots == [first.standardizedFileURL])
        #expect(model.folderAssociationRevision == firstRevision + 1)
        model.remapFolderRoot(from: second, to: third)
        #expect(oldRoots == [first.standardizedFileURL, second.standardizedFileURL])
        #expect(model.folderURL == third.standardizedFileURL)
        #expect(model.folderAssociationRevision == firstRevision + 2)
    }
}
