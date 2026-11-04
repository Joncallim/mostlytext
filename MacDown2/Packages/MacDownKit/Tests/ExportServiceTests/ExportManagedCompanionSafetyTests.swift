import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportManagedCompanionSafetyTests {
    @Test func unknownAndModifiedResourcesArePreservedWithoutBeingReadopted() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let resource = try fixture.resourceURL(first)
        let modified = Data("owner edited this exported image".utf8)
        try modified.write(to: resource)
        let unknown = fixture.assets.appendingPathComponent("owner-notes.txt")
        let notes = Data("unowned notes".utf8)
        try notes.write(to: unknown)
        let next = try await fixture.prepare(2)
        try fixture.write(next)
        #expect(try Data(contentsOf: resource) == modified)
        #expect(try Data(contentsOf: unknown) == notes)
        #expect(try !fixture.inventory().owned.contains { $0.name == resource.lastPathComponent })
        try fixture.assertIdle()
    }

    @Test func matchingLegacyResourceBytesNeverGrantDeletionAuthority() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try FileManager.default.createDirectory(at: fixture.assets, withIntermediateDirectories: false)
        let marker = try ExportAssetOwnerMarker.bytes(primary: "report.html", assets: "report.assets")
        try marker.write(to: fixture.assets.appendingPathComponent(ExportFileWriter.markerFileName))
        let resource = try #require(first.manifest.resources.first)
        let legacy = fixture.assets.appendingPathComponent(resource.identity.fileName)
        try resource.bytes.write(to: legacy)
        try fixture.write(first)
        #expect(try fixture.inventory().owned.isEmpty)
        let next = try await fixture.prepare(2)
        try fixture.write(next)
        #expect(try Data(contentsOf: legacy) == resource.bytes)
        #expect(try !fixture.inventory().owned.contains { $0.name == legacy.lastPathComponent })
        try fixture.assertIdle()
    }

    @Test func aCopiedInventoryCannotAdoptItsNewInode() async throws {
        let fixture = try ExportManagedCompanionFixture()
        try await fixture.write(fixture.prepare(1))
        let primary = try Data(contentsOf: fixture.files.primary)
        let metadata = fixture.assets.appendingPathComponent(ExportCompanionInventoryRecord.fileName)
        let preserved = fixture.assets.appendingPathComponent("original-inventory")
        try FileManager.default.moveItem(at: metadata, to: preserved)
        let copied = try Data(contentsOf: preserved)
        try copied.write(to: metadata)
        try #require(chmod(metadata.path, 0o600) == 0)
        let next = try await fixture.prepare(2)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try Data(contentsOf: metadata) == copied)
        #expect(try Data(contentsOf: preserved) == copied)
        #expect(try Data(contentsOf: fixture.files.primary) == primary)
    }

    @Test(arguments: ["stage-created", "inventory-created"])
    func aCrashBeforeTheReceiptPreservesTheUnknownStageAndBoundsFurtherGrowth(_ point: String) async throws {
        let fixture = try ExportManagedCompanionFixture()
        try await fixture.write(fixture.prepare(1))
        let next = try await fixture.prepare(2)
        var interrupted = false
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { current in
            if current == point, !interrupted {
                interrupted = true
                throw ExportError.unsafePublication
            }
        }
        _ = try? fixture.write(next, hooks: hooks)
        #expect(interrupted)
        let names = try fixture.assetNames()
        let unknown = try #require(names.first { $0.hasPrefix(".mt-companion-") && $0.hasSuffix(".stage") })
        let contents = try Data(contentsOf: fixture.assets.appendingPathComponent(unknown))
        let third = try await fixture.prepare(3)
        for _ in 0 ..< 3 {
            #expect(throws: (any Error).self) { try fixture.write(third) }
            #expect(try fixture.assetNames() == names)
            #expect(try Data(contentsOf: fixture.assets.appendingPathComponent(unknown)) == contents)
        }
    }

    @Test func directoryReplacementCannotRedirectStagingOrRecovery() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let before = try Data(contentsOf: fixture.files.primary)
        let preserved = fixture.files.output.appendingPathComponent("original-assets")
        let next = try await fixture.prepare(2)
        let foreign = Data("foreign directory data".utf8)
        var hooks = ExportPublicationHooks()
        hooks.afterCompanionDirectoryOpened = {
            try? FileManager.default.moveItem(at: fixture.assets, to: preserved)
            try? FileManager.default.createDirectory(at: fixture.assets, withIntermediateDirectories: false)
            try? foreign.write(to: fixture.assets.appendingPathComponent("owner-data"))
        }
        #expect(throws: (any Error).self) { try fixture.write(next, hooks: hooks) }
        #expect(try Data(contentsOf: fixture.files.primary) == before)
        #expect(try Data(contentsOf: fixture.assets.appendingPathComponent("owner-data")) == foreign)
        #expect(try Data(contentsOf: preserved.appendingPathComponent(
            #require(first.manifest.resources.first?.identity.fileName)
        )) == first.manifest.resources.first?.bytes)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: fixture.assets.path)) == ["owner-data"])
    }

    @Test func unknownReferencesUseTheExistingRetentionBudgetInsteadOfDeletingFiles() async throws {
        let fixture = try ExportManagedCompanionFixture()
        var hooks = ExportPublicationHooks()
        hooks.retentionLimit = ExportRetentionLimit(files: 3, bytes: 1024 * 1024)
        let prefix = "[untracked](report.assets/retained.png)\n\n"
        let first = try await fixture.prepare(1, prefix: prefix)
        try fixture.write(first, hooks: hooks)
        let second = try await fixture.prepare(2, prefix: prefix)
        try fixture.write(second, hooks: hooks)
        let before = try Data(contentsOf: fixture.files.primary)
        let third = try await fixture.prepare(3, prefix: prefix)
        #expect(throws: (any Error).self) { try fixture.write(third, hooks: hooks) }
        #expect(try Data(contentsOf: fixture.files.primary) == before)
        #expect(try Data(contentsOf: fixture.resourceURL(first)) == first.manifest.resources.first?.bytes)
        #expect(try Data(contentsOf: fixture.resourceURL(second)) == second.manifest.resources.first?.bytes)
    }

    @Test func aLaterExternalReversionCannotTurnCommittedCleanupIntoRollback() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let prior = try Data(contentsOf: fixture.files.primary)
        let second = try await fixture.prepare(2)
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "retirement-unlinked" {
                throw ExportError.unsafePublication
            }
        }
        let result = try fixture.write(second, hooks: hooks)
        #expect(result.diagnostics.contains { $0.message.contains("could not be finalized") })
        #expect(try !FileManager.default.fileExists(atPath: fixture.resourceURL(first).path))
        try prior.write(to: fixture.files.primary)
        let third = try await fixture.prepare(3)
        #expect(throws: (any Error).self) { try fixture.write(third) }
        #expect(try Data(contentsOf: fixture.files.primary) == prior)
        #expect(try Data(contentsOf: fixture.resourceURL(second)) == second.manifest.resources.first?.bytes)
    }

    @Test(arguments: ["svg", "png"])
    func referencesInsideAPackagedSVGKeepPreviouslyOwnedRasterAssets(_ extensionName: String) async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let previous = try fixture.resourceURL(first)
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"\(previous.lastPathComponent)\"/></svg>"
        try Data(svg.utf8).write(to: fixture.source.appendingPathComponent("linked." + extensionName))
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: "![svg](linked.\(extensionName))",
                sourceGeneration: 2,
                theme: ExportTestSupport.lightTheme(),
                resourceAccess: ExportResourceAccess(openingDirectory: fixture.source)
            ),
            target: fixture.target
        )
        #expect(prepared.manifest.resources.count == 1)
        #expect(!prepared.companionReferencesKnown)
        try fixture.write(prepared)
        #expect(try Data(contentsOf: previous) == first.manifest.resources.first?.bytes)
        #expect(try !fixture.inventory().referencesKnown)
        try fixture.assertIdle()
    }
}
