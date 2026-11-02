import FileCore
import Foundation
import Testing
@testable import Workspace

@Suite("Bootstrap session admission and protected publication")
@MainActor
struct SessionBootstrapAdmissionTests {
    private struct Fixture {
        let directory: URL
        let file: URL
        var store: WorkspaceSessionStore
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("session.json")
        return Fixture(directory: directory, file: file, store: WorkspaceSessionStore(fileURL: file))
    }

    @Test func absentAndValidSessionsPublishVerifiedThroughTheProtocol() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store: any WorkspaceSessionStoring = fixture.store
        #expect(fixture.store.inspectSession() == .absent)
        let session = WorkspaceSession(tabs: [
            TabRecord(id: UUID(), untitledDocumentID: "source", documentRecoveryEpoch: UUID(), isPinned: true,
                      cursorPosition: 5, folderRootBookmark: Data([1, 2, 3])),
        ])
        #expect(store.saveSessionVerified(session))
        #expect(fixture.store.inspectSession() == .readable(session))
        #expect(store.loadSession() == session)
        #expect(store.saveSessionVerified(.empty))
        #expect(store.loadSession() == .empty)
    }

    @Test func corruptFutureDuplicateAndUnknownPrimarySurviveEverySave() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let samples = [
            Data([255]), Data("{bad".utf8), Data("{\"version\":99,\"tabs\":[]}".utf8),
            Data("{\"version\":1,\"version\":1,\"tabs\":[]}".utf8),
            Data("{\"version\":1.0000000000000001,\"tabs\":[]}".utf8),
            Data("{\"version\":true,\"tabs\":[]}".utf8),
            Data("{\"version\":1,\"tabs\":[],\"future\":true}".utf8),
        ]
        for raw in samples {
            try raw.write(to: fixture.file)
            let store: any WorkspaceSessionStoring = fixture.store
            #expect(!fixture.store.inspectSession().permitsPublication)
            #expect(!store.saveSessionVerified(.empty))
            store.saveSession(.empty)
            #expect(try Data(contentsOf: fixture.file) == raw)
        }
    }

    @Test func partialSalvageCannotAuthorizeDroppingUnknownTabsOrNestedFields() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let good = UUID()
        let raw = Data("""
        {"version":1,"tabs":[
          {"id":"\(good.uuidString)","isPinned":false,"untitledDocumentID":"keep"},
          {"id":"\(UUID().uuidString)","isPinned":"future","untitledDocumentID":"preserve"}
        ]}
        """.utf8)
        try raw.write(to: fixture.file)
        let session = try #require(fixture.store.loadSession())
        #expect(session.tabs.map(\.id) == [good])
        #expect(fixture.store.inspectSession() == .partiallyReadable(session))
        let existential: any WorkspaceSessionStoring = fixture.store
        #expect(!existential.saveSessionVerified(session))
        #expect(try Data(contentsOf: fixture.file) == raw)
        var modeled = session
        modeled.tabs[0].encoding = .utf8Default
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(modeled)) as? [String: Any])
        var tabs = try #require(object["tabs"] as? [[String: Any]])
        var encoding = try #require(tabs[0]["encoding"] as? [String: Any])
        encoding["futureNestedField"] = true
        tabs[0]["encoding"] = encoding
        object["tabs"] = tabs
        let nested = try JSONSerialization.data(withJSONObject: object)
        try nested.write(to: fixture.file)
        #expect(fixture.store.loadSession() != nil)
        #expect(!fixture.store.inspectSession().permitsPublication)
        #expect(!fixture.store.saveSessionVerified(.empty))
        #expect(try Data(contentsOf: fixture.file) == nested)
    }

    @Test func firstUnreadableBackupIsNotDeletedOrReplacedByAnotherGeneration() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = Data("first corrupt state".utf8)
        let second = Data("second corrupt state".utf8)
        try first.write(to: fixture.file)
        #expect(fixture.store.loadSession() == nil)
        try second.write(to: fixture.file)
        #expect(fixture.store.loadSession() == nil)
        #expect(!fixture.store.saveSessionVerified(.empty))
        #expect(try Data(contentsOf: fixture.file.appendingPathExtension("unreadable")) == first)
        #expect(try Data(contentsOf: fixture.file) == second)
        let mode = try FileManager.default
            .attributesOfItem(atPath: fixture.file.appendingPathExtension("unreadable").path)
        #expect((mode[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func replacementAfterAdmissionWinsForBothAbsentAndExistingDestinations() throws {
        for existing in [false, true] {
            var fixture = try fixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            if existing {
                #expect(fixture.store.saveSessionVerified(.empty))
            }
            let replacement = Data("{\"version\":99,\"tabs\":[]}".utf8)
            fixture.store.beforePublication = { try replacement.write(to: $0, options: .atomic) }
            #expect(!fixture.store.saveSessionVerified(WorkspaceSession(tabs: [TabRecord(id: UUID())])))
            #expect(try Data(contentsOf: fixture.file) == replacement)
        }
    }

    @Test func symlinkHardLinkDirectoryAndOversizedFilesArePreserved() throws {
        for kind in ["symlink", "hardlink", "directory", "oversized"] {
            let fixture = try fixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let other = fixture.directory.appendingPathComponent("other")
            switch kind {
            case "symlink":
                try Data("preserve".utf8).write(to: other)
                try FileManager.default.createSymbolicLink(at: fixture.file, withDestinationURL: other)
            case "hardlink":
                try Data("preserve".utf8).write(to: fixture.file)
                try FileManager.default.linkItem(at: fixture.file, to: other)
            case "directory": try FileManager.default.createDirectory(
                    at: fixture.file,
                    withIntermediateDirectories: false
                )
            default: try Data(repeating: 65, count: WorkspaceSessionAdmission.maximumBytes + 1).write(to: fixture.file)
            }
            #expect(!fixture.store.inspectSession().permitsPublication)
            #expect(!fixture.store.saveSessionVerified(.empty))
            #expect(FileManager.default.fileExists(atPath: fixture.file.path))
            if kind == "symlink" || kind == "hardlink" {
                #expect(try Data(contentsOf: other) == Data("preserve".utf8))
            }
        }
    }
}
