import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportManagedCompanionRaceTests {
    @Test func changedQuarantineAndOccupiedRestorePreserveBothForeignObjects() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let old = try fixture.resourceURL(first)
        let changed = Data("changed quarantined user bytes".utf8)
        let collision = Data("new original-name occupant".utf8)
        let next = try await fixture.prepare(2)
        var quarantine: URL?
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "retirement-renamed", quarantine == nil {
                let name = try #require(fixture.assetNames().first { $0.hasSuffix(".retired") })
                let url = fixture.assets.appendingPathComponent(name)
                quarantine = url
                try changed.write(to: url)
                try collision.write(to: old)
            }
        }
        let result = try fixture.write(next, hooks: hooks)
        #expect(result.diagnostics.contains { $0.message.contains("could not be finalized") })
        let retained = try #require(quarantine)
        #expect(result.diagnostics.contains { $0.message.contains(retained.path) })
        #expect(try Data(contentsOf: retained) == changed)
        #expect(try Data(contentsOf: old) == collision)
        let primary = try Data(contentsOf: fixture.files.primary)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try Data(contentsOf: retained) == changed)
        #expect(try Data(contentsOf: old) == collision)
        #expect(try Data(contentsOf: fixture.files.primary) == primary)
    }

    @Test func aChangedDisplacedInventoryIsRestoredWithoutOverwritingIt() async throws {
        let fixture = try ExportManagedCompanionFixture()
        try await fixture.write(fixture.prepare(1))
        let next = try await fixture.prepare(2)
        let changed = Data("owner replaced the displaced inventory".utf8)
        var changedStage: URL?
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "inventory-swapped", changedStage == nil {
                let name = try #require(fixture.assetNames().first { $0.hasSuffix(".stage") })
                let url = fixture.assets.appendingPathComponent(name)
                changedStage = url
                try changed.write(to: url)
            }
        }
        let result = try fixture.write(next, hooks: hooks)
        #expect(result.diagnostics.contains { $0.message.contains("could not be finalized") })
        #expect(changedStage != nil)
        let metadata = fixture.assets.appendingPathComponent(ExportCompanionInventoryRecord.fileName)
        #expect(try Data(contentsOf: metadata) == changed)
        let retained = try #require(changedStage)
        #expect(result.diagnostics.contains { $0.message.contains(retained.path) })
        let newlyWrittenInventory = try Data(contentsOf: retained)
        #expect(newlyWrittenInventory != changed)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try Data(contentsOf: metadata) == changed)
        #expect(try Data(contentsOf: retained) == newlyWrittenInventory)
    }

    @Test(arguments: ["symlink", "fifo", "directory", "hardlink"])
    func aForeignObjectAtTheDesiredResourceNameIsNeverRemoved(_ kind: String) async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let next = try await fixture.prepare(2)
        let destination = try fixture.resourceURL(next)
        let foreign = fixture.files.root.appendingPathComponent("foreign-data")
        let bytes = Data("unowned external bytes".utf8)
        try bytes.write(to: foreign)
        switch kind {
        case "symlink": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: foreign)
        case "fifo": try #require(mkfifo(destination.path, 0o600) == 0)
        case "directory": try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        default: try FileManager.default.linkItem(at: foreign, to: destination)
        }
        let descriptor = open(fixture.assets.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        let before = try ExportPublicationFilesystem.childStamp(destination.lastPathComponent, in: descriptor)
        let primary = try Data(contentsOf: fixture.files.primary)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try ExportPublicationFilesystem.childStamp(destination.lastPathComponent, in: descriptor) == before)
        #expect(try Data(contentsOf: foreign) == bytes)
        #expect(try Data(contentsOf: fixture.files.primary) == primary)
    }

    @Test func anAssetAlreadyAdoptedAsTheSourceDocumentCannotBeRetired() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let adopted = try fixture.resourceURL(first)
        _ = try await fixture.prepare(2)
        let result = try await ExportService.exportHTML(
            ExportRequest(text: "![new](image.png)", sourceGeneration: 2, theme: ExportTestSupport.lightTheme(),
                          documentURL: adopted, resourceAccess: ExportResourceAccess(openingDirectory: fixture.source)),
            to: fixture.target, recovery: fixture.files.location
        )
        #expect(!result.diagnostics.contains { $0.message.contains("could not be finalized") })
        #expect(try Data(contentsOf: adopted) == first.manifest.resources.first?.bytes)
        #expect(try !fixture.inventory().owned.contains { $0.name == adopted.lastPathComponent })
        try fixture.assertIdle()
    }
}
