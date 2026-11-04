import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

@Suite("Self-bound companion inventory")
struct ExportCompanionAuthenticationTests {
    @Test func actualCreatedObjectsRestoreTheirExactResourceAndMetadataReceipts() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        let bytes = try codec.seal(fixture.record())
        let stamp = try fixture.writeMetadata(bytes)
        let verified = try codec.open(bytes, metadata: stamp, directory: fixture.directoryStamp)
        let receipt = try ExportOwnedFileReceipt(authenticatedCompanion: verified.receipt(named: fixture.entry.name))
        #expect(try ExportReceiptInspection.verify(receipt, name: fixture.entry.name, in: fixture.directory.descriptor))
        let metadata = try ExportOwnedFileReceipt(authenticatedCompanion: verified.metadataReceipt)
        #expect(try ExportReceiptInspection.verify(
            metadata, name: ExportCompanionInventoryRecord.fileName, in: fixture.directory.descriptor
        ))
        #expect(verified.value.requiredNames == [fixture.entry.name])
        #expect(verified.value.primaryDigest == Data(repeating: 1, count: 32))
    }

    @Test func byteIdenticalCopiedMetadataNeverRestoresOwnership() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        let bytes = try codec.seal(fixture.record())
        _ = try fixture.writeMetadata(bytes)
        let copied = fixture.root.appendingPathComponent("report.assets/copy.json")
        try bytes.write(to: copied, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copied.path)
        let stamp = try ExportPublicationFilesystem.childStamp("copy.json", in: fixture.directory.descriptor)
        #expect(throws: ExportError.self) {
            _ = try codec.open(bytes, metadata: stamp, directory: fixture.directoryStamp)
        }
        #expect(try Data(contentsOf: copied) == bytes)
    }

    @Test func anotherDirectoryLeafOrProducerCannotAuthenticateTheInventory() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        let bytes = try codec.seal(fixture.record())
        let stamp = try fixture.writeMetadata(bytes)
        let other = try ExportCompanionAuthenticationFixture()
        let wrongLeaf = try fixture.bindingForLeaf("report.HTML")
        let foreignCodecs = try [
            fixture.codec(keyBytes: Data(repeating: 0x37, count: 32)),
            fixture.codec(binding: wrongLeaf),
            fixture.codec(binding: other.binding),
        ]
        for foreign in foreignCodecs {
            #expect(throws: ExportError.self) {
                _ = try foreign.open(bytes, metadata: stamp, directory: fixture.directoryStamp)
            }
        }
        #expect(throws: ExportError.self) {
            _ = try codec.open(bytes, metadata: stamp, directory: other.directoryStamp)
        }
    }

    @Test(arguments: ["MostlyText.Export.PrimaryJournal.v1\0", "MostlyText.Export.CompanionPending.v1\0", ""])
    func otherAuthenticationDomainsCannotMintInventoryAuthority(_ domain: String) throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let payload = try JSONEncoder().encode(fixture.record())
        let bytes = try fixture.rawEnvelope(payload: payload, domain: domain)
        let stamp = try fixture.writeMetadata(bytes)
        #expect(throws: ExportError.self) {
            _ = try fixture.codec().open(bytes, metadata: stamp, directory: fixture.directoryStamp)
        }
    }

    @Test func hardlinkedMetadataIsPreservedRatherThanAdopted() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        let bytes = try codec.seal(fixture.record())
        _ = try fixture.writeMetadata(bytes)
        let descriptor = fixture.directory.descriptor
        #expect(linkat(descriptor, ExportCompanionInventoryRecord.fileName, descriptor, "linked.json", 0) == 0)
        let stamp = try ExportPublicationFilesystem.childStamp(ExportCompanionInventoryRecord.fileName, in: descriptor)
        #expect(stamp.links == 2)
        #expect(throws: ExportError.self) {
            _ = try codec.open(bytes, metadata: stamp, directory: fixture.directoryStamp)
        }
    }

    @Test func malformedAuthorityPayloadIsNeverDecodedBeforeAuthentication() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let invalidJSON = Data("this is not a JSON authority payload".utf8)
        let bytes = try fixture.rawEnvelope(payload: invalidJSON, domain: "wrong-domain")
        let stamp = try fixture.writeMetadata(bytes)
        do {
            _ = try fixture.codec().open(bytes, metadata: stamp, directory: fixture.directoryStamp)
            Issue.record("Unauthenticated payload unexpectedly accepted")
        } catch ExportError.unsafePublication {
            // A DecodingError here would prove authority-bearing payload was decoded too early.
        } catch {
            Issue.record("Expected authentication rejection before payload decode: \(error)")
        }
    }

    @Test func duplicateOwnershipAndUnsafeResourceNamesCannotBeSealed() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        #expect(throws: ExportError.self) { _ = try codec.seal(fixture.record(owned: [fixture.entry, fixture.entry])) }
        for name in [
            "../outside",
            "/absolute",
            ".mt-user",
            fixture.entry.name + "/child",
            String(repeating: "a", count: 65),
        ] {
            #expect(throws: ExportError.self) { _ = try codec.seal(fixture.record(required: [name])) }
        }
        #expect(throws: ExportError.self) {
            _ = try codec.seal(fixture.record(required: [fixture.entry.name, fixture.entry.name]))
        }
        let distinct = (0 ..< 513).map { index in
            ExportResourceIdentity(bytes: Data("resource-\(index)".utf8), mimeType: "image/png").fileName
        }
        _ = try codec.seal(fixture.record(required: Array(distinct.prefix(512))))
        #expect(throws: ExportError.self) { _ = try codec.seal(fixture.record(required: distinct)) }
    }

    @Test func unknownReferencesAndAbsentPrimaryCannotFabricateACompleteReferenceSet() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        #expect(throws: ExportError.self) { _ = try codec.seal(fixture.record(referencesKnown: false)) }
        #expect(throws: ExportError.self) { _ = try codec.seal(fixture.record(primary: nil)) }
        _ = try codec.seal(fixture.record(required: [], primary: nil))
        _ = try codec.seal(fixture.record(required: [], referencesKnown: false))
        #expect(throws: ExportError.self) { _ = try codec.seal(fixture.record(primary: Data(repeating: 1, count: 31))) }
    }

    @Test func correctlyAuthenticatedFutureSchemaRemainsUnsupported() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        var object = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(fixture.record())) as? [String: Any])
        object["schema"] = 2
        let bytes = try fixture.rawEnvelope(payload: JSONSerialization.data(
            withJSONObject: object,
            options: .sortedKeys
        ))
        let stamp = try fixture.writeMetadata(bytes)
        #expect(throws: ExportError.self) {
            _ = try fixture.codec().open(bytes, metadata: stamp, directory: fixture.directoryStamp)
        }
    }

    @Test func bothPayloadAndEnvelopeHaveIndependentByteCeilings() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        let oversizedPayload = try fixture.rawEnvelope(payload: Data(
            repeating: 0x61,
            count: ExportCompanionLimits.payloadBytes + 1
        ))
        let payloadStamp = try fixture.writeMetadata(oversizedPayload)
        #expect(throws: ExportError.self) {
            _ = try codec.open(oversizedPayload, metadata: payloadStamp, directory: fixture.directoryStamp)
        }
        let oversizedEnvelope = Data(repeating: 0x61, count: ExportCompanionLimits.envelopeBytes + 1)
        let envelopeStamp = try fixture.writeMetadata(oversizedEnvelope)
        #expect(throws: ExportError.self) {
            _ = try codec.open(oversizedEnvelope, metadata: envelopeStamp, directory: fixture.directoryStamp)
        }
    }
}
