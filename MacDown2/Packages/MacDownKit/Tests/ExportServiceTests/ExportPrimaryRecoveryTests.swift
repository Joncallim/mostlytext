import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

struct ExportPrimaryRecoveryTests {
    private typealias Fixture = ExportPrimaryRecoveryTestSupport.Fixture

    @Test func existingLargerOutputRemainsAuthenticatableAfterNewHTMLLimitIsLowered() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try Data().write(to: fixture.primary)
        let handle = try FileHandle(forWritingTo: fixture.primary)
        defer { try? handle.close() }

        // Sparse logical bytes exercise the older managed-file bound without
        // materializing a large Data value in the test process.
        try handle.truncate(atOffset: UInt64((128 << 20) + 1))
        #expect(try ExportPrimaryRecovery.digest(of: fixture.leaf, in: fixture.descriptor) != nil)

        try handle.truncate(atOffset: UInt64((256 << 20) + 1))
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.digest(of: fixture.leaf, in: fixture.descriptor)
        }
    }

    @Test(arguments: ["prior", "desired", "absent"])
    func authenticatedReopenRetiresOnlyTheKnownScratch(state: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: state == "absent" ? nil : fixture.old)
        if state == "desired" {
            try fixture.desired.write(to: fixture.primary)
        }
        let primary = try ExportPrimaryRecovery.digest(of: fixture.leaf, in: fixture.descriptor)
        do {
            let reopened = try fixture.store()
            try ExportPrimaryRecovery.recover(reopened, primary: fixture.leaf, in: fixture.descriptor)
            #expect(reopened.record.pending == nil)
        }
        #expect(try ExportPublicationFilesystem.primaryBaseline(name, in: fixture.descriptor) == nil)
        #expect(try ExportPrimaryRecovery.digest(of: fixture.leaf, in: fixture.descriptor) == primary)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func anUnknownPrimaryDisablesDestructiveRecovery() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let edited = Data("a later user export".utf8)
        try edited.write(to: fixture.primary)
        let store = try fixture.store()
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(store, primary: fixture.leaf, in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == edited)
        #expect(store.record.pending != nil)
    }

    @Test(arguments: ["bytes", "permissions", "replacement", "symlink", "fifo"])
    func changedScratchNeverBorrowsRecordedOwnership(change: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let scratch = fixture.output.appendingPathComponent(name)
        let preserved = fixture.output.appendingPathComponent("preserved")
        switch change {
        case "bytes": try Data("changed".utf8).write(to: scratch)
        case "permissions": try #require(chmod(scratch.path, 0o400) == 0)
        case "replacement":
            try FileManager.default.moveItem(at: scratch, to: preserved)
            try fixture.desired.write(to: scratch)
        case "symlink":
            try FileManager.default.moveItem(at: scratch, to: preserved)
            try FileManager.default.createSymbolicLink(at: scratch, withDestinationURL: fixture.primary)
        default:
            try FileManager.default.moveItem(at: scratch, to: preserved)
            try #require(mkfifo(scratch.path, 0o600) == 0)
        }
        let before = try ExportPublicationFilesystem.childStamp(name, in: fixture.descriptor)
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor)
        }
        #expect(try ExportPublicationFilesystem.childStamp(name, in: fixture.descriptor) == before)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test(arguments: [false, true])
    func aRestartOnEitherSideOfQuarantineRenameRecovers(renamed: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let quarantine: String
        do {
            let store = try fixture.store()
            quarantine = try store.prepareQuarantine()
            if renamed {
                try #require(renameatx_np(fixture.descriptor, name, fixture.descriptor, quarantine,
                                          UInt32(RENAME_EXCL)) == 0)
            }
        }
        try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor)
        #expect(try ExportPublicationFilesystem.primaryBaseline(name, in: fixture.descriptor) == nil)
        #expect(try ExportPublicationFilesystem.primaryBaseline(quarantine, in: fixture.descriptor) == nil)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func aPromotedPrimaryWithNoScratchIsReconciledWithoutRewritingIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        try #require(renameat(fixture.descriptor, name, fixture.descriptor, fixture.leaf) == 0)
        let before = try ExportPublicationFilesystem.childStamp(fixture.leaf, in: fixture.descriptor)
        try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor)
        #expect(try ExportPublicationFilesystem.childStamp(fixture.leaf, in: fixture.descriptor) == before)
        #expect(try fixture.store().record.pending == nil)
    }

    @Test func aPostRenameMismatchRestoresTheChangedObject() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let later = Data("later writer".utf8)
        var quarantined: String?
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor) { name in
                quarantined = name
                try later.write(to: fixture.output.appendingPathComponent(name))
            }
        }
        #expect(quarantined != nil)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == later)
    }

    @Test func anOccupiedRestorePreservesBothFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        var quarantine: String?
        let other = Data("user bytes".utf8)
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor) { moved in
                quarantine = moved
                try other.write(to: fixture.output.appendingPathComponent(moved))
                try other.write(to: fixture.output.appendingPathComponent(name))
            }
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == other)
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(#require(quarantine))) == other)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func aPrimaryChangedDuringQuarantineDisablesRemovalAndRestoresScratch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let later = Data("later primary".utf8)
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor) { _ in
                try later.write(to: fixture.primary)
            }
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == later)
    }

    @Test func anUnknownQuarantineAfterRestartIsPreservedWithoutInventingItsOrigin() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        let quarantine: String
        do {
            let store = try fixture.store()
            quarantine = try store.prepareQuarantine()
            try #require(renameatx_np(fixture.descriptor, name, fixture.descriptor, quarantine,
                                      UInt32(RENAME_EXCL)) == 0)
        }
        let foreign = Data("changed quarantine".utf8)
        try foreign.write(to: fixture.output.appendingPathComponent(quarantine))
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(quarantine)) == foreign)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test(arguments: ["permissions", "lock", "key"])
    func changedProducerAuthorityBeforeRemovalPreservesTheStagingFile(change: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        #expect(throws: ExportError.self) {
            try ExportPrimaryRecovery.recover(fixture.store(), primary: fixture.leaf, in: fixture.descriptor) { _ in
                switch change {
                case "permissions": try #require(chmod(fixture.location.directory.path, 0o777) == 0)
                case "lock":
                    let lock = fixture.location.directory.appendingPathComponent("producer.lock")
                    try FileManager.default.moveItem(at: lock, to: fixture.root.appendingPathComponent("old-lock"))
                    try Data().write(to: lock)
                    try #require(chmod(lock.path, 0o600) == 0)
                default:
                    try Data(repeating: 0x42, count: 32)
                        .write(to: fixture.location.directory.appendingPathComponent("producer.key"))
                }
            }
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try Data(contentsOf: fixture.primary) == fixture.old)
    }

    @Test func aDifferentLeafCannotAccessAnotherOutputsPendingRecord() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let name = try fixture.stage(prior: fixture.old)
        do {
            let other = try fixture.store(leaf: "report.htm")
            #expect(other.record.pending == nil)
            try ExportPrimaryRecovery.recover(other, primary: "report.htm", in: fixture.descriptor)
        }
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(name)) == fixture.desired)
        #expect(try fixture.store().record.pending != nil)
    }
}
