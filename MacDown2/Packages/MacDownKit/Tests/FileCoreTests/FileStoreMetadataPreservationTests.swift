import Darwin
@testable import FileCore
import Foundation
import Testing

/// Issue #174 — a save must not silently change what the destination file is:
/// its permission bits and extended attributes (Finder tags, quarantine).
@Suite("FileStore metadata preservation (#174)")
struct FileStoreMetadataPreservationTests {
    private static let xattrName = "com.macdown2.test"

    private func mode(of url: URL) throws -> mode_t {
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw POSIXError(.EIO) }
        return info.st_mode & 0o7777
    }

    private func setXattr(_ url: URL, _ value: String) throws {
        let bytes = Array(value.utf8)
        guard setxattr(url.path, Self.xattrName, bytes, bytes.count, 0, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func xattr(_ url: URL) -> String? {
        let size = getxattr(url.path, Self.xattrName, nil, 0, 0, 0)
        guard size >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, Self.xattrName, &buffer, size, 0, 0) == size else { return nil }
        return String(bytes: buffer, encoding: .utf8)
    }

    @Test(arguments: [mode_t(0o700), mode_t(0o600), mode_t(0o644), mode_t(0o755)])
    func aConditionalSavePreservesPermissionBits(_ bits: mode_t) throws {
        let fixture = try FixtureFile(text: "one")
        #expect(chmod(fixture.url.path, bits) == 0)
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try document.save()

        #expect(try FileStore().read(from: fixture.url).content == "two")
        #expect(try mode(of: fixture.url) == bits)
    }

    @Test func aConditionalSavePreservesExtendedAttributes() throws {
        let fixture = try FixtureFile(text: "one")
        try setXattr(fixture.url, "tag")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try document.save()

        #expect(xattr(fixture.url) == "tag")
    }

    @Test func anUnconditionalOverwritePreservesPermissionBitsAndExtendedAttributes() throws {
        let fixture = try FixtureFile(text: "one")
        #expect(chmod(fixture.url.path, 0o700) == 0)
        try setXattr(fixture.url, "tag")

        _ = try FileStore().write("two", to: fixture.url)

        #expect(try FileStore().read(from: fixture.url).content == "two")
        #expect(try mode(of: fixture.url) == 0o700)
        #expect(xattr(fixture.url) == "tag")
    }

    @Test func aNewFilePublishesOwnerOnlyPermissions() throws {
        let fixture = try FixtureFile()

        _ = try FileStore().write("fresh", to: fixture.url)

        #expect(try mode(of: fixture.url) == 0o600)
    }

    /// A read-only (0444) destination is refused rather than silently replaced (review
    /// pass 1 reversed the earlier "overwrite and keep the mode" characterisation): the
    /// owner can write the directory, so the rename-based replace would otherwise succeed.
    @Test func aReadOnlyDestinationIsRefusedAndLeftUntouched() throws {
        let fixture = try FixtureFile(text: "one")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")
        #expect(chmod(fixture.url.path, 0o444) == 0)

        do {
            _ = try document.save()
            Issue.record("expected the read-only destination to be refused")
        } catch {
            guard case .permissionDenied = error else {
                Issue.record("expected .permissionDenied, got \(error)")
                return
            }
        }

        #expect(try FileStore().read(from: fixture.url).content == "one")
        #expect(try mode(of: fixture.url) == 0o444)
    }

    @Test func aConditionalSaveStillAdvancesTheModificationDate() throws {
        let fixture = try FixtureFile(text: "one")
        let old = timeval(tv_sec: 1_000_000_000, tv_usec: 0)
        var times = [old, old]
        #expect(utimes(fixture.url.path, &times) == 0)
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try document.save()

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
        let modified = try #require(attributes[.modificationDate] as? Date)
        #expect(modified.timeIntervalSince1970 > 1_000_000_001)
    }

    @Test func aConditionalSavePreservesAnACLEntry() throws {
        let fixture = try FixtureFile(text: "one")
        let acl = try #require(acl_from_text("!#acl 1\nuser:FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000014:::allow:read"))
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_file(fixture.url.path, ACL_TYPE_EXTENDED, acl) == 0 else {
            Issue.record("could not set a test ACL on this volume")
            return
        }
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try document.save()

        #expect(acl_get_file(fixture.url.path, ACL_TYPE_EXTENDED) != nil)
    }

    @Test func anImmutableDestinationFailsTheSaveAndLeavesNoStagedFileBehind() throws {
        let fixture = try FixtureFile(text: "one")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")
        #expect(chflags(fixture.url.path, UInt32(UF_IMMUTABLE)) == 0)
        defer { _ = chflags(fixture.url.path, 0) }

        #expect(throws: FileStoreError.self) { _ = try document.save() }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
            .filter { $0.contains(".tmp-") }
        #expect(leftovers.isEmpty)
        #expect(try FileStore().read(from: fixture.url).content == "one")
    }
}
