import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportPublicationSafetyTests {
    @Test(arguments: [ExportStyleEmbedding.embedded, .linked])
    func preexistingSidecarSymlinkNeverReceivesWrites(style: ExportStyleEmbedding) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let outside = try ExportPublicationTestSupport.fixture().directory
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: item.assets, withDestinationURL: outside)
        try Data("old primary".utf8).write(to: item.primary)
        let prepared = try ExportPublicationTestSupport.prepared()
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(prepared, to: .html(url: item.primary, mode: .standalone(style: style)))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(try Data(contentsOf: item.primary) == Data("old primary".utf8))
    }

    @Test(arguments: ["missing", "legacy", "unknown", "other-primary"])
    func unknownDirectoriesAndMarkersArePreserved(kind: String) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        try FileManager.default.createDirectory(at: item.assets, withIntermediateDirectories: true)
        let user = item.assets.appendingPathComponent("user.txt")
        try Data("user".utf8).write(to: user)
        let marker = item.assets.appendingPathComponent(ExportFileWriter.markerFileName)
        let bytes: Data? = switch kind {
        case "missing": nil
        case "legacy": Data(ExportFileWriter.markerContent.utf8)
        case "other-primary": try ExportAssetOwnerMarker.bytes(primary: "report.htm", assets: "report.assets")
        default: Data("unrecognized".utf8)
        }
        if let bytes {
            try bytes.write(to: marker)
        }
        try Data("old".utf8).write(to: item.primary)
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: item.target)
        }
        #expect(try Data(contentsOf: user) == Data("user".utf8))
        let observedMarker = try? Data(contentsOf: marker)
        #expect(observedMarker == bytes)
        #expect(try Data(contentsOf: item.primary) == Data("old".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: item.assets.path).count == (bytes == nil ? 1 : 2))
    }

    @Test(arguments: ["report.htm", "report.HTML"])
    func sameStemPrimaryCannotClaimAnExistingOwner(name: String) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let prepared = try ExportPublicationTestSupport.prepared()
        _ = try ExportFileWriter.writeHTML(prepared, to: item.target)
        let before = try Data(contentsOf: item.primary)
        let second = item.directory.appendingPathComponent(name)
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(prepared, to: .html(url: second, mode: .standalone(style: .embedded)))
        }
        #expect(try Data(contentsOf: item.primary) == before)
    }

    @Test(arguments: [false, true])
    func observedPrimaryChangeIsPreserved(originallyAbsent: Bool) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        if !originallyAbsent {
            try Data("old".utf8).write(to: item.primary)
        }
        var entered = false
        let hooks = ExportPublicationHooks(beforePromotion: {
            entered = true
            do {
                try Data("external".utf8).write(to: item.primary, options: .atomic)
            } catch {
                Issue.record("Could not replace primary: \(error)")
            }
        })
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: item.target, hooks: hooks)
        }
        #expect(entered)
        #expect(try Data(contentsOf: item.primary) == Data("external".utf8))
    }

    @Test(arguments: [ExportStyleEmbedding.embedded, .linked])
    func identicalReexportDoesNotRewriteExistingResources(style: ExportStyleEmbedding) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let prepared = try ExportPublicationTestSupport.prepared()
        let target = ExportTarget.html(url: item.primary, mode: .standalone(style: style))
        _ = try ExportFileWriter.writeHTML(prepared, to: target)
        let directory = try ExportPublicationTestSupport.openDirectory(item.assets)
        defer { _ = Darwin.close(directory) }
        let name = try #require(prepared.manifest.resources.first?.identity.fileName)
        let before = try ExportPublicationFilesystem.childStamp(name, in: directory)
        _ = try ExportFileWriter.writeHTML(prepared, to: target)
        #expect(try ExportPublicationFilesystem.childStamp(name, in: directory) == before)
        if style == .linked {
            let css = ExportHTMLWriter.linkedStylesheetResource(for: prepared.stylesheet)
            #expect(try Data(contentsOf: item.assets.appendingPathComponent(css.identity.fileName)) == css.bytes)
            let html = try String(contentsOf: item.primary, encoding: .utf8)
            #expect(html.contains("report.assets/" + css.identity.fileName))
        }
    }

    @Test(arguments: [false, true])
    func symlinkAndFIFOResourceNamesFailWithoutOverwritingThePrimary(fifo: Bool) throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let prepared = try ExportPublicationTestSupport.prepared()
        _ = try ExportFileWriter.writeHTML(prepared, to: item.target)
        let before = try Data(contentsOf: item.primary)
        let resource = try #require(prepared.manifest.resources.first)
        let name = item.assets.appendingPathComponent(resource.identity.fileName)
        try FileManager.default.removeItem(at: name)
        if fifo {
            #expect(mkfifo(name.path, mode_t(S_IRUSR | S_IWUSR)) == 0)
        } else {
            let outside = item.directory.appendingPathComponent("outside.png")
            try resource.bytes.write(to: outside)
            try FileManager.default.createSymbolicLink(at: name, withDestinationURL: outside)
        }
        #expect(throws: ExportError.self) { _ = try ExportFileWriter.writeHTML(prepared, to: item.target) }
        #expect(try Data(contentsOf: item.primary) == before)
    }

    @Test func replacingOpenedSidecarsFailsBeforeAnyResourceWrite() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let outside = item.directory.appendingPathComponent("outside")
        let detached = item.directory.appendingPathComponent("detached")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        var entered = false
        let hooks = ExportPublicationHooks(afterCompanionDirectoryOpened: {
            do {
                try FileManager.default.moveItem(at: item.assets, to: detached)
                try FileManager.default.createSymbolicLink(at: item.assets, withDestinationURL: outside)
                entered = true
            } catch { Issue.record("Could not replace directory: \(error)") }
        })
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: item.target, hooks: hooks)
        }
        #expect(entered)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: detached.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.primary.path))
    }

    @Test func revokedLeaseCleansOnlyItsScratchAndAllowsAFreshExport() throws {
        let item = try ExportPublicationTestSupport.fixture()
        defer { try? FileManager.default.removeItem(at: item.directory) }
        let lease = ExportLifetimeLease()
        let prepared = try ExportPublicationTestSupport.prepared()
        let hooks = ExportPublicationHooks(beforePromotion: { lease.revoke() })
        #expect(throws: CancellationError.self) {
            _ = try ExportFileWriter.writeHTML(prepared, to: item.target, lease: lease, hooks: hooks)
        }
        let prefix = ExportPublicationRetention.scratchPrefix(for: "report.html")
        #expect(try !FileManager.default.contentsOfDirectory(atPath: item.directory.path)
            .contains { $0.hasPrefix(prefix) })
        #expect(!FileManager.default.fileExists(atPath: item.primary.path))
        _ = try ExportFileWriter.writeHTML(prepared, to: item.target)
        #expect(FileManager.default.fileExists(atPath: item.primary.path))
    }
}
