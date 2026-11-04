import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportManagedCompanionStateTests {
    @Test func aLaterDesiredPrimaryCannotUndoAnAlreadyRecordedAbort() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let second = try await fixture.prepare(2)
        let desired = try Data(ExportHTMLWriter.companionHTML(from: second, style: .embedded).utf8)
        var stageHooks = ExportPublicationHooks()
        stageHooks.companionCheckpoint = { point in
            if point == "stage-installation-saved" {
                throw ExportError.unsafePublication
            }
        }
        #expect(throws: (any Error).self) { try fixture.write(second, hooks: stageHooks) }
        let third = try await fixture.prepare(3)
        var abortHooks = ExportPublicationHooks()
        abortHooks.companionCheckpoint = { point in
            if point == "retirement-unlinked" {
                throw ExportError.unsafePublication
            }
        }
        #expect(throws: (any Error).self) { try fixture.write(third, hooks: abortHooks) }
        do {
            let journal = try ExportCompanionJournal(producer: fixture.files.store())
            #expect(journal.pending?.value.phase == .aborted)
        }
        try desired.write(to: fixture.files.primary)
        #expect(throws: (any Error).self) { try fixture.write(third) }
        #expect(try Data(contentsOf: fixture.files.primary) == desired)
        #expect(try Data(contentsOf: fixture.resourceURL(first)) == first.manifest.resources.first?.bytes)
    }

    @Test func aNewDirectoryWithRecordedIdentityCanRecoverItsUnstartedMarker() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "directory-recorded" {
                throw ExportError.unsafePublication
            }
        }
        #expect(throws: (any Error).self) { try fixture.write(first, hooks: hooks) }
        #expect(try fixture.assetNames().isEmpty)
        let next = try await fixture.prepare(2)
        try fixture.write(next)
        #expect(try Data(contentsOf: fixture.resourceURL(next)) == next.manifest.resources.first?.bytes)
        try fixture.assertIdle()
    }

    @Test func aDirectoryCreatedBeforeItsReceiptIsPreservedAndNotAdopted() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "directory-created" {
                throw ExportError.unsafePublication
            }
        }
        #expect(throws: (any Error).self) { try fixture.write(first, hooks: hooks) }
        let owner = fixture.assets.appendingPathComponent("owner-data")
        let bytes = Data("unknown directory occupant".utf8)
        try bytes.write(to: owner)
        let next = try await fixture.prepare(2)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try Data(contentsOf: owner) == bytes)
        #expect(try fixture.assetNames() == ["owner-data"])
    }

    @Test func changingTheProducerKeyMidStagePreservesPrimaryAndAllPublicWorkingObjects() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let primary = try Data(contentsOf: fixture.files.primary)
        let next = try await fixture.prepare(2)
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "stage-receipt-saved" {
                try Data(repeating: 0x42, count: 32)
                    .write(to: fixture.files.location.directory.appendingPathComponent("producer.key"))
            }
        }
        #expect(throws: (any Error).self) { try fixture.write(next, hooks: hooks) }
        let names = try fixture.assetNames()
        #expect(names.contains { $0.hasSuffix(".stage") })
        #expect(try Data(contentsOf: fixture.files.primary) == primary)
        #expect(throws: (any Error).self) { try fixture.write(next) }
        #expect(try fixture.assetNames() == names)
        #expect(try Data(contentsOf: fixture.resourceURL(first)) == first.manifest.resources.first?.bytes)
    }

    @Test func aPublishedInitialInventoryPrecedesObsoleteResourceRetirement() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let old = try fixture.resourceURL(first)
        let second = try await fixture.prepare(2)
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { point in
            if point == "initial-inventory-recorded" {
                throw ExportError.unsafePublication
            }
        }
        let result = try fixture.write(second, hooks: hooks)
        #expect(result.diagnostics.contains { $0.message.contains("could not be finalized") })
        #expect(try Data(contentsOf: old) == first.manifest.resources.first?.bytes)
        let inventory = try fixture.inventory()
        #expect(inventory.owned.count == 2)
        #expect(inventory.requiredNames == second.manifest.resources.map(\.identity.fileName))
        let next = try fixture.write(second)
        #expect(!next.diagnostics.contains { $0.message.contains("could not be finalized") })
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(try fixture.inventory().owned.count == 1)
        try fixture.assertIdle()
    }
}
