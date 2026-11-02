import Darwin
import Foundation

/// A previously observed source object, even if its original name is now gone.
/// It grants no read/write authority and is used only to refuse aliases.
public struct ExportProtectedFileIdentity: Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Authorization-time output identity, retained across rendering. The private
/// descriptor is immutable and publication is serialized by parent identity.
/// This detects observed changes; existing-target rename is not filesystem CAS.
public final class ExportDestinationAdmission: @unchecked Sendable {
    private typealias Filesystem = ExportPublicationFilesystem
    public let url: URL
    let parent: ExportPublicationFilesystem.DirectoryHandle
    let parentStamp: ExportPublicationFilesystem.Stamp
    let primaryStamp: ExportPublicationFilesystem.Stamp?

    public init(capturing url: URL, protecting documents: [URL] = []) throws {
        guard Self.isSafeFileURL(url), Self.isSafeComponent(url.lastPathComponent),
              !url.path.utf8.contains(0)
        else { throw ExportError.unsafePublication }
        self.url = url.standardizedFileURL
        let directory = self.url.deletingLastPathComponent()
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.invalidDestination(directory.path) }
        parent = Filesystem.DirectoryHandle(descriptor)
        parentStamp = try Filesystem.directoryStamp(descriptor)
        primaryStamp = try Filesystem.primaryBaseline(self.url.lastPathComponent, in: descriptor)
        try checkCurrent()
        try checkNoDocumentAliases(documents)
    }

    public func checkCurrent() throws {
        guard try Filesystem.directoryAtPath(url.deletingLastPathComponent().path, matches: parentStamp),
              try Filesystem.primaryBaseline(url.lastPathComponent, in: parent.descriptor) == primaryStamp
        else { throw ExportError.destinationChanged }
    }

    public func checkTarget(_ target: URL) throws {
        guard target.standardizedFileURL.absoluteString.utf8.elementsEqual(url.absoluteString.utf8)
        else { throw ExportError.destinationChanged }
        try checkCurrent()
    }

    public func checkNoDocumentAliases(_ documents: [URL]) throws {
        for document in documents {
            try rejectAlias(of: document)
        }
    }

    public func checkNoFileAliases(_ identities: [ExportProtectedFileIdentity]) throws {
        guard let primaryStamp else { return }
        guard !identities.contains(where: { $0.device == primaryStamp.device && $0.inode == primaryStamp.inode })
        else { throw ExportError.destinationIsOpenDocument }
    }

    /// Publishes already validated immutable bytes through the same bounded,
    /// descriptor-relative primary boundary as HTML. Used by the PDF adapter.
    public func publish(_ bytes: Data, lease: ExportLifetimeLease = ExportLifetimeLease()) throws {
        let input = HTMLFilePublicationInput(
            url: url, mode: .selfContained, bytes: bytes, resources: [],
            assetsDirectoryName: ExportHTMLWriter.assetsDirectoryName(for: url), diagnostics: []
        )
        _ = try ExportFilePublication.write(input, lease: lease, admission: self)
    }

    /// Snapshot a printer-owned candidate beside this output without following
    /// a leaf symlink or reopening the parent pathname. This is read admission,
    /// not proof that an unknown file may be removed during scratch cleanup.
    public func readGeneratedFile(at candidate: URL, maxBytes: Int) throws -> Data? {
        guard Self.isSafeFileURL(candidate), Self.isSafeComponent(candidate.lastPathComponent),
              candidate.deletingLastPathComponent().standardizedFileURL.absoluteString.utf8.elementsEqual(
                  url.deletingLastPathComponent().absoluteString.utf8
              ), !candidate.lastPathComponent.utf8.elementsEqual(url.lastPathComponent.utf8)
        else { throw ExportError.unsafePublication }
        return try Filesystem.readBoundedFile(candidate.lastPathComponent, in: parent.descriptor, maxBytes: maxBytes)
    }

    private func rejectAlias(of document: URL) throws {
        guard document.isFileURL else { throw ExportError.unsafePublication }
        var file = stat()
        if stat(document.path, &file) == 0 {
            if let primaryStamp,
               primaryStamp.device == UInt64(truncatingIfNeeded: file.st_dev), primaryStamp.inode == file.st_ino {
                throw ExportError.destinationIsOpenDocument
            }
        } else if errno != ENOENT, errno != ENOTDIR {
            throw ExportError.unsafePublication
        }
        // Even a missing editor file reserves its own name. Conservative
        // folding may reject distinct names on a case-sensitive volume; it
        // never grants authority from a guessed filesystem normalization.
        guard Self.fold(document.lastPathComponent) == Self.fold(url.lastPathComponent) else { return }
        var directory = stat()
        if stat(document.deletingLastPathComponent().path, &directory) == 0 {
            if parentStamp.sameDirectory(as: Filesystem.Stamp(directory)) {
                throw ExportError.destinationIsOpenDocument
            }
            return
        } else if errno != ENOENT, errno != ENOTDIR {
            throw ExportError.unsafePublication
        }
        if Self.fold(document.standardizedFileURL.path) == Self.fold(url.path) {
            throw ExportError.destinationIsOpenDocument
        }
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isSafeFileURL(_ url: URL) -> Bool {
        let encoded = url.path(percentEncoded: true)
        guard url.isFileURL, url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil,
              url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
              let decoded = encoded.removingPercentEncoding,
              !decoded.utf8.contains(0), !encoded.lowercased().contains("%2f"),
              decoded.utf8.elementsEqual(url.path.utf8)
        else { return false }
        return true
    }

    private static func isSafeComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.utf8.contains(0) && !name.utf8.contains(UInt8(ascii: "/"))
    }
}
