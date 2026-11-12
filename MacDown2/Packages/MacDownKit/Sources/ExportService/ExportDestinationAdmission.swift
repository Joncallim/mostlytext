import Darwin
import Foundation

/// A previously observed source object, even if its original name is now gone.
/// It grants no read/write authority and is used only to refuse aliases.
public struct ExportProtectedFileIdentity: Sendable, Hashable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Authorization-time output identity, retained across rendering. The private
/// descriptor is immutable; protected identities are locked. Publication is
/// serialized by parent identity.
/// This detects observed changes; existing-target rename is not filesystem CAS.
public final class ExportDestinationAdmission: @unchecked Sendable {
    private final class Protection {
        let lock = NSLock()
        var files: Set<ExportProtectedFileIdentity> = []
        var recoveryTargets: Set<ExportProtectedFileIdentity> = []
        var uncertain = false
    }

    private let protection = Protection()
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
        var failure: (any Error)?
        for document in documents {
            do { try rejectAlias(of: document) } catch {
                recordUncertainty(error)
                if failure == nil {
                    failure = error
                }
            }
        }
        if let failure {
            throw failure
        }
    }

    public func checkNoFileAliases(_ identities: [ExportProtectedFileIdentity]) throws {
        try protection.lock.withLock {
            protection.files.formUnion(identities)
            guard protection.recoveryTargets.isDisjoint(with: identities)
            else { throw ExportError.destinationIsOpenDocument }
            if let primaryStamp {
                guard !identities.contains(Self.identity(primaryStamp))
                else { throw ExportError.destinationIsOpenDocument }
            }
        }
    }

    /// Registers an owned working object with the same live-document checks
    /// as the primary. Earlier sources and later publications both protect it.
    func checkRecoveryObject(_ stamp: ExportPublicationFilesystem.Stamp) throws {
        let identity = Self.identity(stamp)
        try protection.lock.withLock {
            protection.recoveryTargets.insert(identity)
            guard !protection.uncertain, !protection.files.contains(identity)
            else { throw ExportError.destinationIsOpenDocument }
        }
    }

    private func recordUncertainty(_ error: any Error) {
        if let error = error as? ExportError, case .destinationIsOpenDocument = error {
            return
        }
        protection.lock.withLock { protection.uncertain = true }
    }

    private static func identity(_ stamp: ExportPublicationFilesystem.Stamp) -> ExportProtectedFileIdentity {
        ExportProtectedFileIdentity(device: stamp.device, inode: stamp.inode)
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
        // Foundation can map physical /private/var to /var when standardizing a parent.
        // Compare both normalized spellings; the read still uses the pinned parent descriptor.
        guard Self.isSafeFileURL(candidate), Self.isSafeComponent(candidate.lastPathComponent),
              candidate.deletingLastPathComponent().standardizedFileURL.absoluteString.utf8.elementsEqual(
                  url.deletingLastPathComponent().standardizedFileURL.absoluteString.utf8
              ), !candidate.lastPathComponent.utf8.elementsEqual(url.lastPathComponent.utf8)
        else { throw ExportError.unsafePublication }
        return try Filesystem.readBoundedFile(candidate.lastPathComponent, in: parent.descriptor, maxBytes: maxBytes)
    }

    private func rejectAlias(of document: URL) throws {
        guard document.isFileURL else { throw ExportError.unsafePublication }
        var file = stat()
        if stat(document.path, &file) == 0 {
            let identity = ExportProtectedFileIdentity(
                device: UInt64(truncatingIfNeeded: file.st_dev), inode: UInt64(file.st_ino)
            )
            try checkNoFileAliases([identity])
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
