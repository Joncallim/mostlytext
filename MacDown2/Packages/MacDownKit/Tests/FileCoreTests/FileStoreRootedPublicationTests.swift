@testable import FileCore
import Foundation
import Testing

@Suite("FileStore rooted publication")
struct FileStoreRootedPublicationTests {
    private struct Fixture {
        let base: URL
        let root: URL
        let child: URL
        let file: URL
        let outside: URL
    }

    private func fixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let child = root.appendingPathComponent("dir", isDirectory: true)
        let file = child.appendingPathComponent("a.md")
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("foo original".utf8).write(to: file)
        return Fixture(base: base, root: root, child: child, file: file, outside: outside)
    }

    @Test func ordinaryReviewedFileReplacementStaysInsideTheSelectedRoot() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.base) }
        let root = try FileStoreRootAuthority(root: item.root)
        let snapshot = try FileStore().readSnapshot(from: item.file)

        _ = try FileStore().write("bar original", to: item.file,
                                  expectedRevision: snapshot.revision, within: root)

        #expect(try String(contentsOf: item.file, encoding: .utf8) == "bar original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.root.path)
            .allSatisfy { !$0.contains(".private-stage-") })
    }

    @Test func movingTheDestinationParentAtTheFinalPublicationBoundaryCannotRewriteItOutside() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.base) }
        let root = try FileStoreRootAuthority(root: item.root)
        let snapshot = try FileStore().readSnapshot(from: item.file)
        let store = FileStore(beforeStagePublication: { _ in
            try FileManager.default.moveItem(at: item.child, to: item.outside)
            try FileManager.default.createSymbolicLink(at: item.child, withDestinationURL: item.outside)
        })

        #expect(throws: FileStoreError.self) {
            _ = try store.write("bar original", to: item.file,
                                expectedRevision: snapshot.revision, within: root)
        }

        #expect(try String(contentsOf: item.outside.appendingPathComponent("a.md"), encoding: .utf8)
            == "foo original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.root.path)
            .allSatisfy { !$0.contains(".private-stage-") })
    }
}
