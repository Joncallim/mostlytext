import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportCompanionJournalTests {
    private typealias Fixture = ExportPrimaryRecoveryTestSupport.Fixture

    private func intent(_ store: ExportJournalStore) -> ExportCompanionPendingRecord {
        ExportCompanionPendingRecord(
            binding: store.companionBinding, assetsName: "report.assets", priorDigest: nil,
            desiredDigest: Data(SHA256.hash(data: Data("desired".utf8))),
            priorReferencesKnown: true, priorRequiredNames: [], desiredReferencesKnown: false, requiredNames: []
        )
    }

    @Test func aPrivatePendingRecordReopensUnderTheSameProducerAndRetiresItsCheckpoint() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let operation: UUID
        do {
            let producer = try fixture.store()
            let journal = try ExportCompanionJournal(producer: producer)
            let record = intent(producer)
            operation = record.operation
            try journal.save(record)
            #expect(journal.pending?.value.operation == operation)
        }
        do {
            let journal = try ExportCompanionJournal(producer: fixture.store())
            #expect(journal.pending?.value.operation == operation)
            try journal.finish()
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: fixture.location.directory.path)
        #expect(Set(entries) == ["producer.key", "producer.lock"])
    }

    @Test func anotherWriterCannotAcquireTheProducerWhileCompanionStateIsLive() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let producer = try fixture.store()
        let journal = try ExportCompanionJournal(producer: producer)
        try journal.save(intent(producer))
        #expect(throws: ExportError.self) { _ = try fixture.store() }
        withExtendedLifetime(journal) {}
    }

    @Test func companionPendingHasItsOwnAuthenticationDomainAndBinding() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        let record = ExportCompanionPendingRecord(
            binding: fixture.binding, assetsName: "report.assets", priorDigest: nil,
            desiredDigest: Data(repeating: 1, count: 32), priorReferencesKnown: true, priorRequiredNames: [],
            desiredReferencesKnown: false, requiredNames: []
        )
        let bytes = try codec.sealPending(record)
        #expect(try codec.openPending(bytes).value.operation == record.operation)
        #expect(throws: (any Error).self) {
            _ = try fixture.codec(binding: fixture.bindingForLeaf("other.html")).openPending(bytes)
        }
        let payload = try JSONEncoder().encode(record)
        for domain in ["MostlyText.Export.PrimaryJournal.v1\0", "MostlyText.Export.CompanionInventory.v1\0"] {
            let foreign = try fixture.rawEnvelope(payload: payload, domain: domain)
            #expect(throws: (any Error).self) { _ = try codec.openPending(foreign) }
        }
    }

    @Test func onlyTheExplicitCompanionLimitCanWriteAndReadLargerPrivateControlData() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let directory = try ExportJournalStorage.open(fixture.location)
        let lock = try ExportJournalStorage.lock(directory.descriptor)
        let bytes = Data(repeating: 0x4D, count: ExportJournalStore.maximumBytes + 1)
        #expect(throws: ExportError.self) {
            _ = try ExportJournalStorage.replace(bytes, named: "primary.json", previous: nil,
                                                 in: directory.descriptor)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.location.directory
                .appendingPathComponent("primary.json").path))
        _ = try ExportJournalStorage.replace(bytes, named: "companion.json", previous: nil,
                                             in: directory.descriptor, limit: .companion)
        #expect(try ExportJournalStorage.read("companion.json", in: directory.descriptor,
                                              maximum: bytes.count, limit: .companion) == bytes)
        #expect(throws: ExportError.self) {
            _ = try ExportJournalStorage.read("companion.json", in: directory.descriptor, maximum: bytes.count)
        }
        #expect(throws: ExportError.self) {
            _ = try ExportJournalStorage.replace(Data(repeating: 1, count: ExportCompanionLimits.envelopeBytes + 1),
                                                 named: "too-large", previous: nil,
                                                 in: directory.descriptor, limit: .companion)
        }
        withExtendedLifetime(lock) {}
    }

    @Test func privateControlAggregateCountsUnknownResidueAndRefusesGrowth() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let directory = try ExportJournalStorage.open(fixture.location)
        let lock = try ExportJournalStorage.lock(directory.descriptor)
        for index in 0 ..< 64 {
            let name = "unowned-\(index)"
            let descriptor = openat(directory.descriptor, name,
                                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            try #require(descriptor >= 0)
            defer { Darwin.close(descriptor) }
            try #require(ftruncate(descriptor, off_t(ExportCompanionLimits.envelopeBytes)) == 0)
        }
        #expect(throws: ExportError.self) {
            try ExportJournalStorage.checkAggregate(directory.descriptor, reserving: 1)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.location.directory.path).count == 66)
        withExtendedLifetime(lock) {}
    }

    @Test func changedPrivatePendingBytesAreNotOverwrittenByALiveJournal() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let producer = try fixture.store()
        let journal = try ExportCompanionJournal(producer: producer)
        let record = intent(producer)
        try journal.save(record)
        let name = try producer.companionBinding.fileName + ".companion"
        let url = fixture.location.directory.appendingPathComponent(name)
        let changed = Data("foreign writer".utf8)
        try changed.write(to: url)
        #expect(throws: (any Error).self) { try journal.save(record) }
        #expect(try Data(contentsOf: url) == changed)
    }

    @Test(arguments: ["schema", "assets", "digest", "directory", "traversal", "duplicate-file", "duplicate-owned"])
    func authenticatedButInvalidPendingModelsNeverMintAuthority(_ change: String) throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        let codec = try fixture.codec()
        var record = ExportCompanionPendingRecord(
            binding: fixture.binding, assetsName: "report.assets", priorDigest: nil,
            desiredDigest: Data(repeating: 1, count: 32), priorReferencesKnown: true, priorRequiredNames: [],
            desiredReferencesKnown: true, requiredNames: [fixture.entry.name]
        )
        record.directory = ExportCompanionObjectIdentity(fixture.directoryStamp)
        record.owned = [fixture.entry]
        record.files = [
            .init(name: fixture.entry.name, temporary: record.temporaryName(suffix: ".stage"),
                  role: .resource, mimeType: fixture.entry.mimeType, receipt: fixture.entry.receipt),
        ]
        #expect(try codec.openPending(codec.sealPending(record)).value.files.count == 1)
        var object = try #require(try JSONSerialization
            .jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        switch change {
        case "schema": object["schema"] = 2
        case "assets": object["assetsName"] = "../outside"
        case "digest": object["desiredDigest"] = Data([1]).base64EncodedString()
        case "directory":
            var directory = try #require(object["directory"] as? [String: Any])
            directory["kind"] = Int(S_IFREG)
            object["directory"] = directory
        case "duplicate-owned":
            let owned = try #require(object["owned"] as? [[String: Any]])
            object["owned"] = owned + owned
        default:
            var files = try #require(object["files"] as? [[String: Any]])
            if change == "traversal" {
                files[0]["temporary"] = "../outside"
            } else {
                files += files
            }
            object["files"] = files
        }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let envelope = try fixture.rawEnvelope(payload: payload, domain: "MostlyText.Export.CompanionPending.v1\0")
        #expect(throws: (any Error).self) { _ = try codec.openPending(envelope) }
    }

    @Test func aMaximumCompletedResourceGenerationFitsTheFixedControlBudget() throws {
        let fixture = try ExportCompanionAuthenticationFixture()
        var entries: [ExportCompanionInventoryRecord.Entry] = []
        for index in 0 ..< ExportResourceBudget.standard.maxResourceCount {
            let bytes = Data("distinct resource \(index)".utf8)
            let identity = ExportResourceIdentity(bytes: bytes, mimeType: "image/png")
            let url = fixture.root.appendingPathComponent("report.assets").appendingPathComponent(identity.fileName)
            try bytes.write(to: url, options: .withoutOverwriting)
            let stamp = try ExportPublicationFilesystem.childStamp(identity.fileName, in: fixture.directory.descriptor)
            try entries.append(.init(name: identity.fileName, mimeType: identity.mimeType,
                                     receipt: ExportJournalRecord.Receipt(ExportOwnedFileReceipt(bytes: bytes,
                                                                                                 stamp: stamp))))
        }
        let names = entries.map(\.name).sorted()
        var record = ExportCompanionPendingRecord(
            binding: fixture.binding, assetsName: "report.assets", priorDigest: nil,
            desiredDigest: Data(repeating: 1, count: 32), priorReferencesKnown: true, priorRequiredNames: [],
            desiredReferencesKnown: true, requiredNames: names
        )
        record.directory = ExportCompanionObjectIdentity(fixture.directoryStamp)
        record.owned = entries
        record.createdNames = names
        let codec = try fixture.codec()
        let bytes = try codec.sealPending(record)
        #expect(bytes.count <= ExportCompanionLimits.envelopeBytes)
        #expect(try codec.openPending(bytes).value.owned.count == ExportResourceBudget.standard.maxResourceCount)
        let inventory = fixture.record(required: names, owned: entries)
        #expect(try codec.seal(inventory).count <= ExportCompanionLimits.envelopeBytes)
    }
}
