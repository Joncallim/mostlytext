import Darwin
import Foundation

extension FileStore {
    /// Publishes a conditional write through an atomic exchange, then verifies
    /// the displaced destination before accepting the new bytes. Every
    /// post-swap exit explicitly owns either our temporary bytes, a confirmed
    /// rollback, or a preserved external recovery file.
    func conditionallyPublish(
        destinationURL: URL,
        expectedRevision: FileRevision,
        hooks: ConditionalPublicationTestHooks?,
        stage: FileStoreStage,
        privateDirectory: FileStorePrivateStageDirectory
    ) throws(FileStoreError) {
        let temporaryURL = privateDirectory.url.appendingPathComponent("stage")
        var ownership: ConditionalPublicationOwnership = .oursAtTemporary
        do {
            try hooks?.beforeExchange?(temporaryURL, destinationURL)
        } catch {
            throw mapWriteError(error)
        }
        let swapError = hooks?.simulateSwapUnsupported == true || !volumeMayExchange(at: destinationURL)
            ? ENOTSUP
            : hooks?.swapOverride?(temporaryURL, destinationURL)
            ?? attemptRenameSwap(privateDirectory, destinationURL)
        if swapError == ENOTSUP {
            // exFAT/FAT32 volumes and many network shares cannot exchange two files.
            try publishWithoutExchange(privateDirectory, destinationURL, expectedRevision: expectedRevision)
            return
        }
        guard swapError == 0 else { throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: swapError) ?? .EIO)) }
        // Backstop for a driver that accepts RENAME_SWAP, returns 0 and performs a plain rename (observed on FAT32):
        // nothing was displaced to the temporary path, so there is no external version to inspect or roll back to.
        // Reporting "preserved a competing version at <temp>" then names a file that does not exist.
        var displaced = stat()
        guard fstatat(privateDirectory.directory, "stage", &displaced, AT_SYMLINK_NOFOLLOW) == 0 else { return }
        ownership = .displacedExternalAtTemporary

        let retirement: FileStoreRetirement
        do {
            try hooks?.beforeDisplacedRead?(temporaryURL)
            retirement = try stage.approvedDisplacedRetirement(expectedRevision)
        } catch {
            try rollbackOrPreserve(temporaryURL, destinationURL, stage: stage,
                                   privateDirectory: privateDirectory, hooks: hooks)
            ownership = .rollbackConfirmed
            do { try stage.refreshAfterRollback() } catch { throw mapWriteError(error) }
            throw mapWriteError(error)
        }

        do {
            try hooks?.afterDisplacedVerification?(temporaryURL)
            try retirement.retire()
        } catch {
            throw mapWriteError(error)
        }
        ownership = .accepted
        assert(ownership == .accepted)
    }

    /// Carries the destination's permission bits, ACL, extended attributes
    /// (Finder tags, quarantine) and the cosmetic `UF_HIDDEN`/`UF_NODUMP`
    /// flags onto the staged file before it is published (#174).
    ///
    /// Deliberately not `COPYFILE_STAT`: that would also copy timestamps (a
    /// save must advance the modification date) and flags such as
    /// `UF_IMMUTABLE` (which would make the staged file unswappable and
    /// undeletable). The owner is not carried: the saving user owns the new
    /// file. Permission bits are mandatory — a save never silently widens a
    /// 0600 file. ACL/xattr copying is skipped only when the volume does not
    /// support them (`ENOTSUP`/`ENOATTR`); any other failure is surfaced
    /// rather than silently dropping metadata.
    func carryMetadata(from destination: URL, to stage: FileStoreStage,
                       privateDirectory: FileStorePrivateStageDirectory) throws(FileStoreError) {
        let source = openat(privateDirectory.parent, destination.lastPathComponent,
                            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard source >= 0 else { throw currentErrnoWriteError() }
        defer { _ = Darwin.close(source) }
        var info = stat()
        guard fstat(source, &info) == 0 else { throw currentErrnoWriteError() }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw .notRegularFile }
        guard fchmod(stage.descriptor, info.st_mode & 0o7777) == 0 else { throw currentErrnoWriteError() }
        let cosmeticFlags = info.st_flags & UInt32(UF_HIDDEN | UF_NODUMP)
        if cosmeticFlags != 0, fchflags(stage.descriptor, cosmeticFlags) != 0, errno != ENOTSUP {
            throw currentErrnoWriteError()
        }
        let copied = fcopyfile(source, stage.descriptor, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
        if copied != 0, errno != ENOTSUP, errno != ENOATTR {
            throw currentErrnoWriteError()
        }
    }

    private func currentErrnoWriteError() -> FileStoreError {
        mapWriteError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
    }

    /// Restores the displaced file, or — when it cannot be restored — preserves it
    /// beside the destination and reports where.
    private func rollbackOrPreserve(
        _ temporaryURL: URL,
        _ destinationURL: URL,
        stage: FileStoreStage,
        privateDirectory: FileStorePrivateStageDirectory,
        hooks: ConditionalPublicationTestHooks?
    ) throws(FileStoreError) {
        guard rollbackDisplacedFile(
            temporaryURL,
            destinationURL,
            stage: stage,
            privateDirectory: privateDirectory,
            hooks: hooks
        ) else {
            let recoveryURL = preserveDisplacedFile(at: temporaryURL, for: destinationURL,
                                                    privateDirectory: privateDirectory)
            throw .conditionalPublicationRecoveryRequired(recoveryURL)
        }
    }

    private func rollbackDisplacedFile(
        _ temporaryURL: URL,
        _ destinationURL: URL,
        stage: FileStoreStage,
        privateDirectory: FileStorePrivateStageDirectory,
        hooks: ConditionalPublicationTestHooks?
    ) -> Bool {
        // A second external writer may have replaced our newly published file.
        // It owns the destination now; preserve the earlier displaced writer
        // instead of swapping either external version away.
        do {
            guard try stage.matchesOwnedFile(in: privateDirectory.parent,
                                             name: destinationURL.lastPathComponent) else { return false }
            try hooks?.beforeRollbackSwap?(temporaryURL, destinationURL)
            try renameSwap(privateDirectory, destinationURL)
            // The destination can change after the pre-swap validation. In
            // that case the exchange leaves the newer external object at the
            // temporary path. It must be preserved, never mistaken for our
            // bytes and deleted by the write cleanup path.
            guard try stage.matchesOwnedFile(in: privateDirectory.directory, name: "stage") else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func preserveDisplacedFile(at temporaryURL: URL, for destinationURL: URL,
                                       privateDirectory: FileStorePrivateStageDirectory) -> URL {
        let recoveryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            Self.companionName(for: destinationURL, infix: "external-recovery")
        )
        if renameatx_np(privateDirectory.directory, "stage", privateDirectory.parent,
                        recoveryURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0 {
            return recoveryURL
        }
        // The displaced bytes remain in the open private directory. The
        // original URL is still the best recovery location when its name has
        // not been moved by another writer.
        return temporaryURL
    }

    private func matchesExpectedBaseline(_ actual: FileRevision, _ expected: FileRevision) -> Bool {
        let identityMatches: Bool = if let actualID = actual.fileObjectID, let expectedID = expected.fileObjectID {
            actualID == expectedID
        } else {
            actual.fileObjectID == nil && expected.fileObjectID == nil
        }
        return identityMatches
            && actual.modificationDate == expected.modificationDate
            && actual.fileSize == expected.fileSize
            && actual.sha256 == expected.sha256
    }

    /// Whether the volume holding `destination` advertises exchange support. FAT32 on current macOS reports
    /// `volumeSupportsSwapRenaming == false` yet still accepts the flag and does a plain rename that DELETES the
    /// previous file, so every save looked like a failed swap and a competing write was silently destroyed. Unknown
    /// (`nil`, e.g. some network shares) still tries the exchange, which reports `ENOTSUP` itself.
    private func volumeMayExchange(at destination: URL) -> Bool {
        let values = try? destination.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeSupportsSwapRenamingKey])
        return values?.volumeSupportsSwapRenaming != false
    }

    /// 0 on success, otherwise the errno of the failed exchange.
    private func attemptRenameSwap(_ privateDirectory: FileStorePrivateStageDirectory,
                                   _ destination: URL) -> Int32 {
        let result = renameatx_np(privateDirectory.directory, "stage", privateDirectory.parent,
                                  destination.lastPathComponent, UInt32(RENAME_SWAP))
        return result == 0 ? 0 : errno
    }

    private func renameSwap(_ privateDirectory: FileStorePrivateStageDirectory,
                            _ destination: URL) throws(FileStoreError) {
        let error = attemptRenameSwap(privateDirectory, destination)
        guard error == 0 else {
            throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO))
        }
    }

    /// Fallback for volumes without `RENAME_SWAP`: re-verify the destination
    /// against the baseline immediately before an atomic `rename(2)` replace.
    /// Unlike the exchange there is no displaced object to inspect afterwards, so
    /// a writer that wins in the instant between the check and the rename is not
    /// detected — the best a volume without exchange can offer — but a stale
    /// baseline is still refused and the replace itself stays atomic.
    private func publishWithoutExchange(
        _ privateDirectory: FileStorePrivateStageDirectory,
        _ destinationURL: URL,
        expectedRevision: FileRevision
    ) throws(FileStoreError) {
        let current = try readRevision(from: destinationURL)
        guard matchesExpectedBaseline(current, expectedRevision) else { throw .fileChangedDuringRead }
        let result = renameat(privateDirectory.directory, "stage", privateDirectory.parent,
                              destinationURL.lastPathComponent)
        guard result == 0 else {
            throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
        }
    }
}

struct ConditionalPublicationTestHooks: Sendable {
    /// Controlled mutation after the final named-directory check and before
    /// the exchange. Production callers never install this hook.
    let beforeExchange: (@Sendable (URL, URL) throws -> Void)?
    let beforeDisplacedRead: (@Sendable (URL) throws -> Void)?
    let afterDisplacedVerification: (@Sendable (URL) throws -> Void)?
    let beforeRollbackSwap: (@Sendable (URL, URL) throws -> Void)?
    /// Behave as on a volume whose exchange returns `ENOTSUP`.
    let simulateSwapUnsupported: Bool
    /// Replaces the exchange itself (returns 0 or an errno) — e.g. FAT32's "accept the flag, plain-rename, return 0".
    let swapOverride: (@Sendable (URL, URL) -> Int32)?

    init(
        beforeExchange: (@Sendable (URL, URL) throws -> Void)?,
        beforeDisplacedRead: (@Sendable (URL) throws -> Void)? = nil,
        afterDisplacedVerification: (@Sendable (URL) throws -> Void)? = nil,
        beforeRollbackSwap: (@Sendable (URL, URL) throws -> Void)? = nil,
        simulateSwapUnsupported: Bool = false,
        swapOverride: (@Sendable (URL, URL) -> Int32)? = nil
    ) {
        self.beforeExchange = beforeExchange
        self.beforeDisplacedRead = beforeDisplacedRead
        self.afterDisplacedVerification = afterDisplacedVerification
        self.beforeRollbackSwap = beforeRollbackSwap
        self.simulateSwapUnsupported = simulateSwapUnsupported
        self.swapOverride = swapOverride
    }

    init(
        beforeDisplacedRead: (@Sendable (URL) throws -> Void)? = nil,
        afterDisplacedVerification: (@Sendable (URL) throws -> Void)? = nil,
        beforeRollbackSwap: (@Sendable (URL, URL) throws -> Void)? = nil,
        simulateSwapUnsupported: Bool = false,
        swapOverride: (@Sendable (URL, URL) -> Int32)? = nil
    ) {
        self.init(beforeExchange: nil, beforeDisplacedRead: beforeDisplacedRead,
                  afterDisplacedVerification: afterDisplacedVerification,
                  beforeRollbackSwap: beforeRollbackSwap,
                  simulateSwapUnsupported: simulateSwapUnsupported, swapOverride: swapOverride)
    }
}

private enum ConditionalPublicationOwnership: Equatable {
    case oursAtTemporary
    case displacedExternalAtTemporary
    case rollbackConfirmed
    case accepted
    case externalRecoveryPreserved(URL)
}
