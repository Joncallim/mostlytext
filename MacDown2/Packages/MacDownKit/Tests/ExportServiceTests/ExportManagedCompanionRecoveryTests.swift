@testable import ExportService
import Foundation
import Testing

struct ExportManagedCompanionRecoveryTests {
    private static let points = [
        "intent-saved", "stage-intent-saved", "stage-receipt-saved", "stage-renamed",
        "stage-installation-saved", "commit-recorded", "retirement-intent-saved",
        "retirement-renamed", "retirement-unlinked", "inventory-intent-saved",
        "inventory-receipt-saved", "inventory-swapped", "inventory-finalized", "companion-finished",
    ]

    @Test func oneHundredChangedExportsAlternateModesWithoutAccumulatingOwnedOrphans() async throws {
        let fixture = try ExportManagedCompanionFixture()
        var maximumEntries = 0
        var interruptedCycles = 0

        for version in 1 ... 100 {
            var mode: HTMLExportMode = switch version % 3 {
            case 0: .selfContained
            case 1: .standalone(style: .embedded)
            default: .standalone(style: .linked)
            }
            if version % 5 == 0, mode == .selfContained {
                mode = .standalone(style: .embedded)
            }
            let prepared = try await fixture.prepare(version, mode: mode)
            #expect(prepared.companionReferencesKnown)
            if version % 5 == 0 {
                let point = Self.points[interruptedCycles % Self.points.count]
                var interrupted = false
                var hooks = ExportPublicationHooks()
                hooks.companionCheckpoint = { current in
                    if current == point, !interrupted {
                        interrupted = true
                        throw ExportError.unsafePublication
                    }
                }
                _ = try? fixture.write(prepared, mode: mode, hooks: hooks)
                #expect(interrupted)
                interruptedCycles += 1
            }
            let result = try fixture.write(prepared, mode: mode)
            #expect(result.diagnostics.allSatisfy { $0.severity != .error })
            #expect(!result.diagnostics.contains { $0.message.contains("could not be finalized") })
            let html = try String(contentsOf: fixture.files.primary, encoding: .utf8)
            if mode == .selfContained {
                #expect(html.contains("data:image/png;base64,"))
            } else {
                let resource = try #require(prepared.manifest.resources.first)
                #expect(html.contains(resource.identity.fileName))
                #expect(try Data(contentsOf: fixture.resourceURL(prepared)) == resource.bytes)
                #expect(try fixture.inventory().requiredNames.contains(resource.identity.fileName))
            }
            maximumEntries = try max(maximumEntries, fixture.assetNames().count)
            try fixture.assertIdle()
        }
        #expect(interruptedCycles == 20)
        #expect(maximumEntries <= 4) // Marker + inventory + current image + optional stylesheet.
        #expect(try fixture.inventory().owned.count <= 2)
    }

    @Test(arguments: [
        "intent-saved", "stage-intent-saved", "stage-receipt-saved", "stage-renamed",
        "stage-installation-saved", "commit-recorded", "retirement-intent-saved", "retirement-renamed",
        "retirement-unlinked", "inventory-intent-saved", "inventory-receipt-saved", "inventory-swapped",
        "inventory-finalized", "companion-finished",
    ])
    func aFreshExportReconcilesBothSidesOfEachDurableTransition(_ point: String) async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let before = try Data(contentsOf: fixture.files.primary)
        let second = try await fixture.prepare(2)
        var interrupted = false
        var hooks = ExportPublicationHooks()
        hooks.companionCheckpoint = { current in
            if current == point, !interrupted {
                interrupted = true
                throw ExportError.unsafePublication
            }
        }
        let result = try? fixture.write(second, hooks: hooks)
        #expect(interrupted)
        let after = try Data(contentsOf: fixture.files.primary)
        if let result {
            #expect(after != before)
            #expect(result.diagnostics.contains { $0.message.contains("could not be finalized") })
        } else {
            #expect(after == before)
            #expect(try Data(contentsOf: fixture.resourceURL(first)) == first.manifest.resources.first?.bytes)
        }
        let third = try await fixture.prepare(3)
        let resumed = try fixture.write(third)
        #expect(!resumed.diagnostics.contains { $0.message.contains("could not be finalized") })
        #expect(try Data(contentsOf: fixture.resourceURL(third)) == third.manifest.resources.first?.bytes)
        #expect(try fixture.inventory().owned.count == 1)
        try fixture.assertIdle()
    }

    @Test func selfContainedFirstExportCreatesNoCompanionDirectory() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let prepared = try await fixture.prepare(1, mode: .selfContained)
        try fixture.write(prepared, mode: .selfContained)
        #expect(!FileManager.default.fileExists(atPath: fixture.assets.path))
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: fixture.files.location.directory.path))
            == ["producer.key", "producer.lock"])
    }

    @Test func unknownReferenceClosureRetainsOwnedResourcesUntilALaterClosedExport() async throws {
        let fixture = try ExportManagedCompanionFixture()
        let first = try await fixture.prepare(1)
        try fixture.write(first)
        let old = try fixture.resourceURL(first)
        let second = try await fixture.prepare(2, prefix: "[old](report.assets/\(old.lastPathComponent))\n\n")
        #expect(!second.companionReferencesKnown)
        try fixture.write(second)
        #expect(try Data(contentsOf: old) == first.manifest.resources.first?.bytes)
        #expect(try !fixture.inventory().referencesKnown)
        #expect(try fixture.inventory().requiredNames.isEmpty)
        let third = try await fixture.prepare(3)
        try fixture.write(third)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(try fixture.inventory().referencesKnown)
        #expect(try fixture.inventory().owned.count == 1)
        try fixture.assertIdle()
    }
}
