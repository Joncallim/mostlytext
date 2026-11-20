import Darwin
@testable import FileCore
import Foundation
import Testing

@Suite("FileStore stage path authority")
struct FileStoreStagePathAuthorityTests {
    @Test func stageCreationUsesTheOpenedDirectoryAfterItsNameMoves() throws {
        let fixture = try FixtureFile()
        let original = fixture.directory.appendingPathComponent("private")
        let displaced = fixture.directory.appendingPathComponent("displaced-private")
        let attacker = fixture.directory.appendingPathComponent("attacker")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: attacker, withIntermediateDirectories: false)
        let directory = open(original.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        try #require(directory >= 0)
        defer { _ = Darwin.close(directory) }
        try FileManager.default.moveItem(at: original, to: displaced)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: attacker)

        let bytes = Data("authored bytes".utf8)
        let stage = try FileStoreStage(bytes: bytes, at: original.appendingPathComponent("stage"),
                                       directoryDescriptor: directory)
        #expect(try Data(contentsOf: displaced.appendingPathComponent("stage")) == bytes)
        #expect(!FileManager.default.fileExists(atPath: attacker.appendingPathComponent("stage").path))
        try stage.retire()
    }

    @Test(arguments: ["absent", "unconditional"])
    func aLatePrivateDirectorySwapCannotRedirectOtherPublications(_ kind: String) throws {
        let fixture = try FixtureFile(text: kind == "absent" ? nil : "original")
        let fileURL = fixture.url
        let directoryURL = fixture.directory
        let attacker = directoryURL.appendingPathComponent("attacker")
        let displaced = directoryURL.appendingPathComponent("displaced-private")
        try FileManager.default.createDirectory(at: attacker, withIntermediateDirectories: false)
        try Data("attacker bytes".utf8).write(to: attacker.appendingPathComponent("stage"))

        let store = FileStore(beforeStagePublication: { temporary in
            try FileManager.default.moveItem(at: temporary.deletingLastPathComponent(), to: displaced)
            try FileManager.default.createSymbolicLink(
                at: temporary.deletingLastPathComponent(), withDestinationURL: attacker
            )
        })
        if kind == "absent" {
            _ = try store.write("our bytes", to: fileURL, destinationBaseline: .absent)
        } else {
            _ = try store.write("our bytes", to: fileURL)
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "our bytes")
        #expect(try String(contentsOf: attacker.appendingPathComponent("stage"), encoding: .utf8)
            == "attacker bytes")
    }

    @Test func aLatePrivateDirectorySwapCannotRedirectTheExchange() throws {
        let fixture = try FixtureFile(text: "original")
        let fileURL = fixture.url
        let directoryURL = fixture.directory
        let attacker = directoryURL.appendingPathComponent("attacker")
        let displaced = directoryURL.appendingPathComponent("displaced-private")
        try FileManager.default.createDirectory(at: attacker, withIntermediateDirectories: false)
        try Data("attacker bytes".utf8).write(to: attacker.appendingPathComponent("stage"))

        let store = FileStore(conditionalPublicationHooks: .init(
            beforeExchange: { temporary, _ in
                try FileManager.default.moveItem(at: temporary.deletingLastPathComponent(), to: displaced)
                try FileManager.default.createSymbolicLink(
                    at: temporary.deletingLastPathComponent(), withDestinationURL: attacker
                )
            },
            beforeDisplacedRead: { _ in
                let visible = try String(contentsOf: fileURL, encoding: .utf8)
                #expect(visible == "our bytes")
            }
        ))

        _ = try store.write("our bytes", to: fileURL,
                            destinationBaseline: FileStore().destinationBaseline(at: fileURL))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "our bytes")
        #expect(try String(contentsOf: attacker.appendingPathComponent("stage"), encoding: .utf8)
            == "attacker bytes")
    }

    @Test func aReplacedPrivateDirectoryNeverPublishesTheReplacementStage() throws {
        let fixture = try FixtureFile(text: "original")
        let fileURL = fixture.url
        let directoryURL = fixture.directory
        let attacker = directoryURL.appendingPathComponent("attacker")
        let displaced = directoryURL.appendingPathComponent("displaced-private")
        try FileManager.default.createDirectory(at: attacker, withIntermediateDirectories: false)
        try Data("attacker bytes".utf8).write(to: attacker.appendingPathComponent("stage"))

        let store = FileStore(
            afterBaselineVerification: { _ in
                let entries = try FileManager.default.contentsOfDirectory(
                    at: directoryURL, includingPropertiesForKeys: nil
                )
                let privateDirectory = try #require(entries.first {
                    $0.lastPathComponent.contains(".private-stage-")
                })
                try FileManager.default.moveItem(at: privateDirectory, to: displaced)
                try FileManager.default.createSymbolicLink(at: privateDirectory, withDestinationURL: attacker)
            },
            conditionalPublicationHooks: .init(beforeDisplacedRead: { _ in
                let visible = try String(contentsOf: fileURL, encoding: .utf8)
                #expect(visible != "attacker bytes", "The replacement stage must never reach the destination")
            })
        )

        #expect(throws: FileStoreError.self) {
            _ = try store.write("our bytes", to: fileURL,
                                destinationBaseline: FileStore().destinationBaseline(at: fileURL))
        }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "original")
        #expect(try String(contentsOf: attacker.appendingPathComponent("stage"), encoding: .utf8) == "attacker bytes")
    }
}
