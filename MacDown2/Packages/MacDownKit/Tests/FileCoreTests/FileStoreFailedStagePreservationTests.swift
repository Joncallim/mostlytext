import Darwin
@testable import FileCore
import Foundation
import Testing

struct FileStoreFailedStagePreservationTests {
    @Test(arguments: [false, true], [false, true])
    func failedPublicationPreservesAChangedStage(conditional: Bool, replacement: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("filestore-review-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("source.md")
        let backup = root.appendingPathComponent("owned-stage-backup")
        let original = Data("original".utf8)
        let foreign = Data("foreign writer".utf8)
        try original.write(to: target)
        let baseline = try FileStore().readRevision(from: target)
        let store = FileStore(beforePublication: { _ in
            let candidates = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.contains(".tmp-") }
            guard candidates.count == 1, let stage = candidates.first else { throw POSIXError(.ENOENT) }
            if replacement {
                try FileManager.default.moveItem(at: stage, to: backup)
            }
            try foreign.write(to: stage)
            throw POSIXError(.EIO)
        })
        #expect(throws: FileStoreError.self) {
            try store.write("ours", to: target, expectedRevision: conditional ? baseline : nil)
        }
        #expect(try Data(contentsOf: target) == original)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let retainedForeign = files.filter { (try? Data(contentsOf: $0)) == foreign }
        #expect(retainedForeign.count == 1, "Failed-save cleanup must not delete an externally changed stage")
        if replacement {
            #expect(try Data(contentsOf: backup) == Data("ours".utf8))
        }
    }

    @Test func aFailedUnchangedStageIsRetiredWithoutChangingTheDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("filestore-review-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("source.md")
        try Data("original".utf8).write(to: target)
        let store = FileStore(beforePublication: { _ in throw POSIXError(.EIO) })
        #expect(throws: FileStoreError.self) { try store.write("ours", to: target) }
        #expect(try Data(contentsOf: target) == Data("original".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source.md"])
    }
}
