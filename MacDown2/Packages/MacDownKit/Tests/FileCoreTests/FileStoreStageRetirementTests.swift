import Darwin
@testable import FileCore
import Foundation
import Testing

struct FileStoreStageRetirementTests {
    private let bytes = Data("owned staging bytes".utf8)

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stage-retirement-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func creationDoesNotOverwriteAnExistingObject() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("stage")
        let foreign = Data("existing writer".utf8)
        try foreign.write(to: url)
        #expect(throws: (any Error).self) { _ = try FileStoreStage(bytes: bytes, at: url) }
        #expect(try Data(contentsOf: url) == foreign)
    }

    @Test(arguments: ["same-bytes", "permissions", "xattr", "symlink", "fifo"])
    func changedObjectsArePreservedBeforeRetirement(change: String) throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("stage")
        let backup = root.appendingPathComponent("owned-backup")
        let stage = try FileStoreStage(bytes: bytes, at: url)
        switch change {
        case "same-bytes":
            try FileManager.default.moveItem(at: url, to: backup)
            try bytes.write(to: url)
        case "permissions":
            #expect(chmod(url.path, 0o400) == 0)
        case "xattr":
            let value = [UInt8]("external metadata".utf8)
            #expect(setxattr(url.path, "com.mostlytext.stage-review", value, value.count, 0, 0) == 0)
        case "symlink":
            try FileManager.default.moveItem(at: url, to: backup)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: backup)
        default:
            try FileManager.default.moveItem(at: url, to: backup)
            #expect(mkfifo(url.path, 0o600) == 0)
        }
        #expect(throws: FileStoreError.self) { try stage.retire() }
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        if change == "fifo" {
            #expect(info.st_mode & mode_t(S_IFMT) == mode_t(S_IFIFO))
        }
        if change == "symlink" {
            #expect(info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK))
        }
        if change == "same-bytes" {
            #expect(try Data(contentsOf: url) == bytes)
        }
        if change == "xattr" {
            #expect(getxattr(url.path, "com.mostlytext.stage-review", nil, 0, 0, 0) > 0)
        }
    }

    @Test(arguments: [false, true])
    func changedQuarantineIsRestoredOrReportedWithoutOverwritingANewOccupant(occupied: Bool) throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("stage")
        let foreign = Data("changed quarantined bytes".utf8)
        let occupant = Data("new original-path occupant".utf8)
        let stage = try FileStoreStage(bytes: bytes, at: url)
        var changedURL: URL?
        do {
            try stage.retire(afterQuarantine: { isolated in
                changedURL = isolated
                try foreign.write(to: isolated)
                if occupied {
                    try occupant.write(to: url)
                }
            })
            Issue.record("Expected changed quarantine to require recovery")
        } catch let FileStoreError.conditionalPublicationRecoveryRequired(recovery) {
            let expected = occupied ? try #require(changedURL) : url
            #expect(recovery == expected)
            #expect(try Data(contentsOf: recovery) == foreign)
            if occupied {
                #expect(try Data(contentsOf: url) == occupant)
            }
        }
    }

    @Test(arguments: [false, true])
    func changedDisplacedBaselineIsPreservedAfterVerification(replacement: Bool) throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("document.md")
        let backup = root.appendingPathComponent("approved-baseline-backup")
        let foreign = Data("external writer after baseline verification".utf8)
        _ = try FileStore().write("original", to: url)
        let baseline = try FileStore().readRevision(from: url)
        let store = FileStore(conditionalPublicationHooks: .init(afterDisplacedVerification: { displaced in
            if replacement {
                try FileManager.default.moveItem(at: displaced, to: backup)
            }
            try foreign.write(to: displaced)
        }))
        #expect(throws: FileStoreError.self) { try store.write("ours", to: url, expectedRevision: baseline) }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(files.filter { (try? Data(contentsOf: $0)) == foreign }.count == 1)
        #expect(try Data(contentsOf: url) == Data("ours".utf8))
        if replacement {
            #expect(try Data(contentsOf: backup) == Data("original".utf8))
        }
    }

    @Test func unchangedQuarantineIsRemovedAndAnAbsentStageIsHarmless() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("stage")
        let stage = try FileStoreStage(bytes: bytes, at: url)
        try stage.retire()
        try stage.retire()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
