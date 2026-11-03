import CryptoKit
import Darwin
import Foundation

/// Minted from known staging bytes and their observed object, or restored by
/// the authenticated private producer store. A pathname/public marker alone
/// never establishes removal authority.
struct ExportOwnedFileReceipt {
    typealias Stamp = ExportPublicationFilesystem.Stamp
    let stamp: Stamp
    let digest: Data

    init(bytes: Data, stamp: Stamp) throws {
        guard stamp.kind == mode_t(S_IFREG), stamp.size == bytes.count,
              bytes.count <= ExportResourceBudget.maxFinalHTMLUTF8Bytes else { throw ExportError.unsafePublication }
        self.stamp = stamp
        digest = Data(SHA256.hash(data: bytes))
    }

    /// An archived model alone cannot authorize removal. This capability is
    /// created only by the private store after envelope authentication.
    init(authenticated: ExportJournalStore.AuthenticatedReceipt) throws {
        let archived = authenticated.value
        guard archived.stamp.kind == mode_t(S_IFREG), archived.stamp.size >= 0,
              archived.stamp.size <= ExportResourceBudget.maxFinalHTMLUTF8Bytes,
              archived.digest.count == SHA256.byteCount else { throw ExportError.unsafePublication }
        stamp = archived.stamp
        digest = archived.digest
    }

    func matchesMetadata(_ actual: Stamp) -> Bool {
        stamp.device == actual.device && stamp.inode == actual.inode && stamp.kind == actual.kind
            && stamp.size == actual.size && stamp.birthSeconds == actual.birthSeconds
            && stamp.birthNanoseconds == actual.birthNanoseconds
            && stamp.modifiedSeconds == actual.modifiedSeconds && stamp.modifiedNanoseconds == actual
            .modifiedNanoseconds
            && stamp.owner == actual.owner && stamp.group == actual.group && stamp.permissions == actual.permissions
            && stamp.links == actual.links && stamp.flags == actual.flags
    }
}

enum ExportReceiptInspection {
    private typealias Filesystem = ExportPublicationFilesystem

    static func verify(_ receipt: ExportOwnedFileReceipt, name: String, in directory: Int32,
                       matching snapshot: ExportPublicationFilesystem.Stamp? = nil,
                       afterOpen: (() throws -> Void)? = nil) throws -> Bool {
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0), !name.utf8.contains(UInt8(ascii: "/"))
        else { throw ExportError.unsafePublication }
        let descriptor = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.unsafePublication }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else { throw Filesystem.posixFailure() }
        let observed = Filesystem.Stamp(initial)
        guard receipt.matchesMetadata(observed), observed == (snapshot ?? receipt.stamp) else { return false }
        try afterOpen?()
        let digest = try hash(descriptor, expectedBytes: Int(observed.size))
        var final = stat()
        guard fstat(descriptor, &final) == 0 else { throw Filesystem.posixFailure() }
        let named = try Filesystem.childStamp(name, in: directory)
        return Filesystem.Stamp(final) == observed && receipt.digest == Data(digest) && named == observed
    }

    static func hash(_ descriptor: Int32, expectedBytes: Int) throws -> SHA256.Digest {
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total = 0
        while true {
            let remaining = expectedBytes - total
            let wanted = remaining >= buffer.count ? buffer.count : remaining + 1
            let count = Darwin.read(descriptor, &buffer, wanted)
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw ExportPublicationFilesystem.posixFailure() }
            if count == 0 {
                break
            }
            guard count <= remaining else { throw ExportError.unsafePublication }
            total += count
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
        }
        guard total == expectedBytes else { throw ExportError.unsafePublication }
        return hasher.finalize()
    }
}
