import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportJournalStorageRecoveryTests {
    private typealias Fixture = ExportPrimaryRecoveryTestSupport.Fixture

    @Test(arguments: ["truncated", "payload", "key", "oversized", "schema", "binding"])
    func corruptOrForeignRecordsNeverAuthorizeRemoval(change: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let url = try fixture.recordURL
        let original = try Data(contentsOf: url)
        switch change {
        case "truncated": try original.prefix(17).write(to: url)
        case "oversized": try Data(repeating: 0x41, count: ExportJournalStore.maximumBytes + 1).write(to: url)
        case "key":
            try Data(repeating: 0x42, count: 32)
                .write(to: fixture.location.directory.appendingPathComponent("producer.key"))
        default:
            var envelope = try #require(JSONSerialization.jsonObject(with: original) as? [String: String])
            let encodedPayload = try #require(envelope["payload"])
            var payload = try #require(Data(base64Encoded: encodedPayload))
            if change == "payload" {
                payload.append(0x20) // valid JSON whitespace still invalidates authentication
            } else {
                var object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
                if change == "schema" {
                    object["schema"] = 999
                } else {
                    var binding = try #require(object["binding"] as? [String: Any])
                    binding["leaf"] = Data("report.htm".utf8).base64EncodedString()
                    object["binding"] = binding
                }
                payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                // A producer-authenticated but semantically wrong record is refused too.
                let key = try Data(contentsOf: fixture.location.directory.appendingPathComponent("producer.key"))
                let code = HMAC<SHA256>.authenticationCode(
                    for: Data("MostlyText.Export.PrimaryJournal.v1\0".utf8) + payload, using: SymmetricKey(data: key)
                )
                envelope["authentication"] = Data(code).base64EncodedString()
            }
            envelope["payload"] = payload.base64EncodedString()
            try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: url)
        }
        #expect(throws: (any Error).self) { _ = try fixture.store() }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test(arguments: [
        "key-mode",
        "record-mode",
        "root-mode",
        "key-symlink",
        "record-symlink",
        "key-hardlink",
        "record-fifo",
    ])
    func unsafePrivateStorageIsRefused(change: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let key = fixture.location.directory.appendingPathComponent("producer.key")
        let record = try fixture.recordURL
        switch change {
        case "key-mode": try #require(chmod(key.path, 0o644) == 0)
        case "record-mode": try #require(chmod(record.path, 0o644) == 0)
        case "root-mode": try #require(chmod(fixture.location.directory.path, 0o755) == 0)
        case "key-hardlink": try FileManager.default.linkItem(
                at: key,
                to: fixture.root.appendingPathComponent("key-link")
            )
        case "record-fifo":
            try FileManager.default.removeItem(at: record)
            try #require(mkfifo(record.path, 0o600) == 0)
        default:
            let victim = change == "key-symlink" ? key : record
            let outside = fixture.root.appendingPathComponent("untouched")
            try Data(contentsOf: victim).write(to: outside)
            try FileManager.default.removeItem(at: victim)
            try FileManager.default.createSymbolicLink(at: victim, withDestinationURL: outside)
        }
        #expect(throws: (any Error).self) { _ = try fixture.store() }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func anExistingDirectoryWithoutAKeyIsNeverProvisionedOrAdopted() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.location.directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        #expect(throws: ExportError.self) { _ = try fixture.store() }
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: fixture.location.directory.path).isEmpty)
    }

    @Test func aGrantingACLIsRefusedWithoutChangingIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        do { _ = try fixture.store() }
        let acl = try #require(acl_from_text("!#acl 1\nuser:FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000014:::allow:read"))
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        try #require(acl_set_file(fixture.location.directory.path, ACL_TYPE_EXTENDED, acl) == 0)
        #expect(throws: ExportError.self) { _ = try fixture.store() }
        let after = try #require(acl_get_file(fixture.location.directory.path, ACL_TYPE_EXTENDED))
        defer { acl_free(UnsafeMutableRawPointer(after)) }
        var entry: acl_entry_t?
        #expect(acl_get_entry(after, 0, &entry) == 0)
    }

    @Test func competingWritersCannotBothOwnThePrivateStore() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        do {
            let first = try fixture.store()
            #expect(throws: ExportError.self) { _ = try fixture.store() }
            withExtendedLifetime(first) {}
        }
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func anExportInsideThePrivateStoreCannotReplaceProducerState() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        do { _ = try fixture.store() }
        let key = fixture.location.directory.appendingPathComponent("producer.key")
        let bytes = try Data(contentsOf: key)
        #expect(throws: ExportError.self) {
            _ = try ExportFileWriter.writeHTML(
                ExportPublicationTestSupport.prepared(), to: .html(url: key, mode: .selfContained),
                recovery: fixture.location
            )
        }
        #expect(try Data(contentsOf: key) == bytes)
    }

    @Test func anOverfullStoreRefusesGrowthWithoutDeletingUnknownEntries() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        do { _ = try fixture.store() }
        for index in 0 ..< 1022 {
            try Data().write(to: fixture.location.directory.appendingPathComponent("unknown-\(index)"))
        }
        #expect(throws: ExportError.self) { _ = try fixture.store() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.location.directory.path).count == 1024)
    }

    @Test func cancellationDuringFirstProvisioningDoesNotLeaveAnEmptyKey() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let output = fixture.output
        let location = fixture.location
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let descriptor = open(output.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { Issue.record("Could not open fixture"); return }
            defer { Darwin.close(descriptor) }
            // The bounded control-data critical section completes despite
            // cancellation. No product or owner storage is used.
            do {
                _ = try ExportJournalStore(location: location,
                                           parent: ExportPublicationFilesystem.directoryStamp(descriptor),
                                           leaf: "report.html")
            } catch is CancellationError {
                Issue.record("Private provisioning unexpectedly abandoned its checkpoint")
            } catch { Issue.record("Provisioning failed: \(error)") }
        }
        await task.value
        let key = location.directory.appendingPathComponent("producer.key")
        #expect(try Data(contentsOf: key).count == 32)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func successfulOutputsDoNotAccumulateIdleRecords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for index in 0 ..< 100 {
            let store = try fixture.store(leaf: "chosen-output-\(index).html")
            try store.finish()
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.location.directory.path)
        #expect(Set(names) == Set(["producer.key", "producer.lock"]))
    }

    @Test(arguments: [1020, 1021])
    func checkpointCapacityIsAdmittedBeforePublicStaging(unknownFiles: Int) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        do { _ = try fixture.store() }
        try fixture.old.write(to: fixture.primary)
        for index in 0 ..< unknownFiles {
            try Data().write(to: fixture.location.directory.appendingPathComponent("unknown-\(index)"))
        }
        let target = ExportTarget.html(url: fixture.primary, mode: .selfContained)
        if unknownFiles == 1020 {
            _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: target,
                                               recovery: fixture.location)
            #expect(try Data(contentsOf: fixture.primary) != fixture.old)
        } else {
            #expect(throws: ExportError.self) {
                _ = try ExportFileWriter.writeHTML(ExportPublicationTestSupport.prepared(), to: target,
                                                   recovery: fixture.location)
            }
            #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.location.directory.path).count
            == unknownFiles + 2)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: fixture.output.path)
            .contains { $0.hasPrefix(".mt-") })
    }

    @Test func replacingTheProducerKeyMidOperationCannotCommitAReceipt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = try fixture.store()
        try Data(repeating: 0x42, count: 32)
            .write(to: fixture.location.directory.appendingPathComponent("producer.key"))
        #expect(throws: ExportError.self) { try store.finish() }
        #expect(try !FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }
}
