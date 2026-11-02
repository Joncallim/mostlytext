import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportTemporaryRetirementTests {
    @Test func signedDeviceIdentitiesDoNotTrapOrAliasPositiveOnes() {
        var negative = stat()
        negative.st_dev = -1
        negative.st_ino = 1
        var positive = negative
        positive.st_dev = 1
        let negativeStamp = ExportPublicationFilesystem.Stamp(negative)
        let positiveStamp = ExportPublicationFilesystem.Stamp(positive)
        #expect(negativeStamp.device != positiveStamp.device)
        #expect(negativeStamp.inode == positiveStamp.inode)
    }

    @Test(arguments: [false, true])
    func aReplacedTemporaryIsRestoredInsteadOfDeleted(sameBytes: Bool) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let descriptor = try ExportPublicationTestSupport.openDirectory(item.directory)
        defer { _ = Darwin.close(descriptor) }
        let name = ".mt-test.stage"
        let url = item.directory.appendingPathComponent(name)
        let ours = Data("ours".utf8)
        let foreign = sameBytes ? ours : Data("foreign".utf8)
        try ours.write(to: url)
        let stamp = try ExportPublicationFilesystem.childStamp(name, in: descriptor)
        try foreign.write(to: url, options: .atomic)
        #expect(throws: ExportError.self) {
            try ExportPublicationFilesystem.retireTemporary(ours, name: name, expected: stamp, in: descriptor)
        }
        #expect(try Data(contentsOf: url) == foreign)
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.directory.path) == [name])
    }

    @Test func anOccupiedRestorePathPreservesBothFilesAndNamesRecovery() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let descriptor = try ExportPublicationTestSupport.openDirectory(item.directory)
        defer { _ = Darwin.close(descriptor) }
        let name = ".mt-test.stage"
        let url = item.directory.appendingPathComponent(name)
        try Data("ours".utf8).write(to: url)
        let stamp = try ExportPublicationFilesystem.childStamp(name, in: descriptor)
        try Data("foreign".utf8).write(to: url, options: .atomic)
        let occupy: (String) -> Void = { _ in
            do {
                try Data("new occupant".utf8).write(to: url)
            } catch {
                Issue.record("Could not occupy the restore name: \(error)")
            }
        }
        do {
            try ExportPublicationFilesystem.retireTemporary(
                Data("ours".utf8), name: name, expected: stamp, in: descriptor, afterQuarantine: occupy
            )
            Issue.record("Expected explicit recovery")
        } catch let ExportError.publicationRecoveryRequired(recovery) {
            #expect(try Data(contentsOf: recovery) == Data("foreign".utf8))
        }
        #expect(try Data(contentsOf: url) == Data("new occupant".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.directory.path).count == 2)
    }
}
