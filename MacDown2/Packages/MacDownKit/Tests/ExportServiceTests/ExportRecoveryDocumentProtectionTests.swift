import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportRecoveryDocumentProtectionTests {
    @Test func anOpenedRecoveryFileIsPreservedByTheOrdinaryWriter() throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let source = fixture.output.appendingPathComponent(name)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary, protecting: [source])
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
                admission: admission, lease: ExportLifetimeLease(), recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: source) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        #expect(try fixture.store().record.pending != nil)
    }
}

extension ExportRecoveryDocumentProtectionTests {
    @Test(arguments: [false, true])
    func retainedSourceIdentityProtectsRecoveryEvenWithoutAPrimary(existing: Bool) throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: existing ? fixture.old : nil)
        let stamp = try ExportPublicationFilesystem.childStamp(name, in: fixture.descriptor)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary)
        try admission.checkNoFileAliases([ExportProtectedFileIdentity(device: stamp.device, inode: stamp.inode)])
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
                admission: admission, lease: ExportLifetimeLease(), recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try ExportPrimaryRecovery.digest(of: fixture.leaf, in: fixture.descriptor)
            == (existing ? Data(SHA256.hash(data: fixture.old)) : nil))
    }

    @Test func aBatchConflictStillRetainsProtectionForItsLaterSource() throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let source = fixture.output.appendingPathComponent(name)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary)
        #expect(throws: ExportError.self) { try admission.checkNoDocumentAliases([fixture.primary, source]) }
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
                admission: admission, lease: ExportLifetimeLease(), recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: source) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func anUnusableDocumentReferenceRefusesCleanupUntilAFreshAdmission() throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let source = fixture.output.appendingPathComponent(name)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary)
        let invalid = try #require(URL(string: "https://example.invalid/document"))
        #expect(throws: ExportError.self) { try admission.checkNoDocumentAliases([invalid]) }
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
                admission: admission, lease: ExportLifetimeLease(), recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: source) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        _ = try ExportFileWriter.writeHTML(
            ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
            recovery: fixture.location
        )
    }

    @Test func anOpenedQuarantineIsPreservedOnRestart() throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let quarantine: String
        do {
            let store = try fixture.store()
            quarantine = try store.prepareQuarantine()
            try #require(renameatx_np(fixture.descriptor, name, fixture.descriptor, quarantine,
                                      UInt32(RENAME_EXCL)) == 0)
        }
        let source = fixture.output.appendingPathComponent(quarantine)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary, protecting: [source])
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
                admission: admission, lease: ExportLifetimeLease(), recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: source) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func aDocumentAdoptedDuringRecoveryKeepsItsQuarantinedObject() throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        _ = try fixture.stage(prior: fixture.old)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary)
        let lease = ExportLifetimeLease()
        let protection = ExportRecoveryProtection(admission: admission, lease: lease)
        var adopted: URL?
        do {
            let store = try fixture.store()
            #expect(throws: ExportError.self) {
                try ExportPrimaryRecovery.recover(store, primary: fixture.leaf, in: fixture.descriptor,
                                                  protection: protection) { name in
                    let source = fixture.output.appendingPathComponent(name)
                    adopted = source
                    do { try admission.checkNoDocumentAliases([source]) } catch { lease.revoke() }
                }
            }
        }
        let source = try #require(adopted)
        #expect(try Data(contentsOf: source) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        #expect(throws: CancellationError.self) { try lease.checkActive() }
        #expect(try fixture.store().record.pending != nil)
        // A fresh admission after the document closes can reconcile the record.
        _ = try ExportFileWriter.writeHTML(
            ExportPublicationTestSupport.prepared(), to: .html(url: fixture.primary, mode: .selfContained),
            recovery: fixture.location
        )
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test(arguments: [false, true])
    func aFreshPrimaryAdoptedBeforePromotionIsNeitherMovedNorDeleted(durable: Bool) throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        try fixture.old.write(to: fixture.primary)
        let admission = try ExportDestinationAdmission(capturing: fixture.primary)
        let lease = ExportLifetimeLease()
        var adopted: URL?
        let hooks = ExportPublicationHooks(beforePromotion: {
            do {
                let name = try #require(FileManager.default.contentsOfDirectory(atPath: fixture.output.path)
                    .first { $0.hasPrefix(".mt-") && $0.hasSuffix(".html.tmp") })
                let source = fixture.output.appendingPathComponent(name)
                adopted = source
                do { try admission.checkNoDocumentAliases([source]) } catch { lease.revoke() }
            } catch { Issue.record("Could not adopt the staged fixture: \(error)") }
        })
        let input = HTMLFilePublicationInput(
            url: fixture.primary, mode: .selfContained, bytes: fixture.desired, resources: [],
            assetsDirectoryName: "report.assets", diagnostics: []
        )
        #expect(throws: ExportError.self) {
            _ = try ExportFilePublication.write(input, lease: lease, hooks: hooks, admission: admission,
                                                recovery: durable ? fixture.location : nil)
        }
        #expect(try Data(contentsOf: #require(adopted)) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func memoryRetirementDoesNotRestoreOrDeleteANewlyAdoptedQuarantine() throws {
        let fixture = try ExportPrimaryRecoveryTestSupport.Fixture()
        defer { fixture.cleanup() }
        let name = ".mt-\(UUID().uuidString).stage"
        let admission = try ExportDestinationAdmission(capturing: fixture.primary)
        let lease = ExportLifetimeLease()
        let protection = ExportRecoveryProtection(admission: admission, lease: lease)
        let stamp = try ExportPublicationFilesystem.withScratch(
            fixture.desired, name: name, in: fixture.descriptor, retainOnSuccess: true
        ) { _, stamp in stamp }
        let receipt = try ExportOwnedFileReceipt(bytes: fixture.desired, stamp: stamp)
        var adopted: URL?
        #expect(throws: ExportError.self) {
            try ExportFileRetirement
                .retire(receipt, name: name, in: fixture.descriptor, protection: protection) { moved in
                    let source = fixture.output.appendingPathComponent(moved)
                    adopted = source
                    do { try admission.checkNoDocumentAliases([source]) } catch { lease.revoke() }
                }
        }
        #expect(try Data(contentsOf: #require(adopted)) == fixture.desired)
        #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent(name).path))
    }
}
