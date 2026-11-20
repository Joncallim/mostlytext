import Darwin
import Foundation

/// What a Save As destination looked like when the user authorised it (#183
/// F22). Publishing against this baseline means a file another process created,
/// replaced or modified in the meantime is never silently overwritten — the same
/// external-writer protection an ordinary Save has.
public enum DestinationBaseline: Sendable, Equatable {
    /// No file existed at the destination.
    case absent
    /// The destination existed with exactly this content/identity.
    case revision(FileRevision)
}

public extension FileStore {
    /// The destination's current baseline: `.absent` for a missing path, the
    /// file's revision for a regular file. Anything else (a directory, an
    /// unreadable file) throws, so Save As is refused rather than guessed at.
    func destinationBaseline(at url: URL) throws(FileStoreError) -> DestinationBaseline {
        do {
            return try .revision(readRevision(from: url))
        } catch .fileMissing {
            return .absent
        }
    }
}

public extension FileDocument {
    /// The baseline Save As to `url` must publish against, or `nil` for the
    /// pre-existing unconditional replacement.
    ///
    /// - A symbolic-link destination (or one that cannot be classified) keeps
    ///   the previous behaviour: the link itself is replaced.
    /// - The document's own file, while it is healthy (backing available, no
    ///   pending external change, a known revision), keeps ordinary Save's
    ///   external-writer protection: the baseline is what the document last
    ///   knew. The own file is recognised by path *or* physical identity, so a
    ///   case-variant spelling cannot drop the protection.
    /// - Anything else — including a missing/unavailable or externally changed
    ///   backing file the user is resolving by choosing the same name — is the
    ///   user explicitly authorising the destination's current state, captured
    ///   fresh.
    func saveAsBaseline(for url: URL) throws(FileStoreError) -> DestinationBaseline? {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return nil
        }
        let current = try fileStore.destinationBaseline(at: url)
        if case .absent = current {
            return .absent
        }
        guard let known = lastKnownRevision, isHealthyBackedDocument else { return current }
        let samePath = url.standardizedFileURL == fileURL?.standardizedFileURL
        if case let .revision(revision) = current, !samePath {
            let sameObject = revision.fileObjectID != nil && revision.fileObjectID == known.fileObjectID
            return sameObject ? .revision(known) : current
        }
        return samePath ? .revision(known) : current
    }

    private var isHealthyBackedDocument: Bool {
        guard pendingExternalRevision == nil, state != .conflict else { return false }
        if case .unavailable = backingState {
            return false
        }
        return true
    }
}

extension FileStore {
    /// Publishes `temporaryURL` at `destinationURL` only if nothing exists
    /// there (`RENAME_EXCL`); an existing file means the baseline was stale.
    func publishExclusively(_ privateDirectory: FileStorePrivateStageDirectory,
                            to destinationURL: URL) throws(FileStoreError) {
        let result = renameatx_np(privateDirectory.directory, "stage", privateDirectory.parent,
                                  destinationURL.lastPathComponent, UInt32(RENAME_EXCL))
        guard result == 0 else {
            let code = errno
            if code == EEXIST {
                throw .fileChangedDuringRead
            }
            if code == ENOTSUP || code == EINVAL {
                // An unsupported exclusive rename cannot preserve the absent
                // baseline against another writer. Refuse instead of falling
                // back to a path-based check followed by a replacing rename.
                throw mapWriteError(POSIXError(.ENOTSUP))
            }
            throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO))
        }
    }

    /// Folds the two ways a caller can express a destination expectation into
    /// one revision to match and whether the destination must not exist.
    static func resolveBaseline(
        _ expectedRevision: FileRevision?,
        _ baseline: DestinationBaseline?
    ) -> (FileRevision?, Bool) {
        assert(expectedRevision == nil || baseline == nil, "pass one baseline, not both")
        switch baseline {
        case let .revision(revision): return (revision, false)
        case .absent: return (nil, true)
        case nil: return (expectedRevision, false)
        }
    }

    func requireAbsentIfNeeded(_ requireAbsent: Bool, at url: URL) throws(FileStoreError) {
        if requireAbsent, FileManager.default.fileExists(atPath: url.path) {
            throw .fileChangedDuringRead
        }
    }

    /// Publishes the staged file: conditionally against `expectedRevision`,
    /// exclusively when the destination must not exist, else by replacement.
    func publishStaged(
        to url: URL,
        expectedRevision: FileRevision?,
        requireAbsent: Bool,
        stage: FileStoreStage,
        privateDirectory: FileStorePrivateStageDirectory
    ) throws(FileStoreError) {
        do {
            if let expectedRevision {
                try conditionallyPublish(
                    destinationURL: url,
                    expectedRevision: expectedRevision,
                    hooks: conditionalPublicationHooks,
                    stage: stage,
                    privateDirectory: privateDirectory
                )
            } else if requireAbsent {
                try publishExclusively(privateDirectory, to: url)
            } else {
                var named = stat()
                if fstatat(privateDirectory.parent, url.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW) == 0 {
                    guard named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                        throw FileStoreError.permissionDenied
                    }
                } else if errno != ENOENT {
                    throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                }
                guard renameat(privateDirectory.directory, "stage", privateDirectory.parent,
                               url.lastPathComponent) == 0 else {
                    throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                }
            }
        } catch let error as FileStoreError {
            throw error
        } catch {
            throw mapWriteError(error)
        }
    }
}
