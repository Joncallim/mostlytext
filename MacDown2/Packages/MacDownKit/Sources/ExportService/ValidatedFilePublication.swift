import CryptoKit
import Darwin
import Foundation

/// Shared filesystem boundary for ordinary and optional validated HTML. Open directory
/// descriptors keep every staging operation in the directory actually checked;
/// changing a pathname to a symlink cannot redirect a later read or write.
/// A process with write access to the destination can still race the final
/// pathname checks or change exported files after publication. This is not an
/// atomic transaction across the primary and its companions.
enum ExportFilePublication {
    private typealias Filesystem = ExportPublicationFilesystem
    private typealias DirectoryHandle = Filesystem.DirectoryHandle
    private typealias Stamp = Filesystem.Stamp

    private struct StagedCompanions {
        let directory: DirectoryHandle
        let stamp: Stamp
        let entries: [(name: String, stamp: Stamp)]
        let urls: [URL]
    }

    private final class StagedPrimary {
        let directory: DirectoryHandle
        let name: String
        let stamp: Stamp
        let bytes: Data
        let protection: ExportRecoveryProtection
        private var promoted = false
        private var retirementAttempted = false

        init(directory: DirectoryHandle, name: String, stamp: Stamp, bytes: Data,
             protection: ExportRecoveryProtection) {
            self.directory = directory
            self.name = name
            self.stamp = stamp
            self.bytes = bytes
            self.protection = protection
        }

        func promote(as destination: String, absent: Bool) throws {
            let result = absent
                ? renameatx_np(directory.descriptor, name, directory.descriptor, destination, UInt32(RENAME_EXCL))
                : renameat(directory.descriptor, name, directory.descriptor, destination)
            guard result == 0
            else { throw Filesystem.posixFailure() }
            promoted = true
        }

        func publishing(retireOnFailure: (() throws -> Void)? = nil, _ operation: () throws -> Void) throws {
            do { try operation() } catch {
                if let retireOnFailure {
                    // A durable receipt must also own the quarantine transition.
                    // Do not fall back to an unrecorded deinit cleanup on failure.
                    retirementAttempted = true
                    try retireOnFailure()
                } else {
                    try discard()
                }
                throw error
            }
        }

        private func discard() throws {
            guard !promoted, !retirementAttempted else { return }
            retirementAttempted = true
            try ExportFileRetirement.retire(ExportOwnedFileReceipt(bytes: bytes, stamp: stamp),
                                            name: name, in: directory.descriptor, protection: protection)
        }

        deinit { try? discard() }
    }

    static func write(
        _ validated: ValidatedExportHTML, lease: ExportLifetimeLease,
        afterCompanionDirectoryOpened: (() -> Void)?, beforePromotion: (() -> Void)?,
        recovery: ExportRecoveryLocation? = nil
    ) throws -> ExportResult {
        guard case let .html(url, mode) = validated.target, validated.bytesAreIntact()
        else { throw ExportError.validatedPublicationRejected }
        let input = HTMLFilePublicationInput(
            url: url, mode: mode, bytes: validated.utf8, resources: validated.resources,
            assetsDirectoryName: validated.assetsDirectoryName, diagnostics: validated.diagnostics,
            referencesKnown: validated.companionReferencesKnown
        )
        return try write(input, lease: lease, hooks: .init(
            afterCompanionDirectoryOpened: afterCompanionDirectoryOpened, beforePromotion: beforePromotion
        ), recovery: recovery)
    }

    static func write(
        _ input: HTMLFilePublicationInput, lease: ExportLifetimeLease,
        hooks: ExportPublicationHooks = .init(),
        admission: ExportDestinationAdmission? = nil,
        recovery: ExportRecoveryLocation? = nil
    ) throws -> ExportResult {
        try validate(input)
        try Task.checkCancellation()
        try lease.checkActive()
        let authorization = try admission ?? ExportDestinationAdmission(capturing: input.url)
        try authorization.checkTarget(input.url)
        let parentURL = input.url.deletingLastPathComponent()
        let parent = authorization.parent
        let parentStamp = authorization.parentStamp
        return try ExportPublicationGate.withDirectory(device: parentStamp.device, inode: parentStamp.inode) {
            try Task.checkCancellation()
            try lease.checkActive()
            guard try Filesystem.directoryAtPath(parentURL.path, matches: parentStamp)
            else { throw ExportError.unsafePublication }
            let journal = try recovery.map {
                try openJournal($0, parent: parentStamp, leaf: input.url.lastPathComponent)
            }
            let protection = ExportRecoveryProtection(admission: authorization, lease: lease)
            // The process lock must outlive the complete publication cutoff.
            defer { withExtendedLifetime(journal) {} }
            let prefix = ExportPublicationRetention.scratchPrefix(for: input.url.lastPathComponent)
            let priorDigest = try reconcile(journal, for: input.url, in: parent, protection: protection)
            try ExportPublicationRetention.checkParent(parent.descriptor, scratchPrefix: prefix)
            try authorization.checkTarget(input.url)
            let staged = try stageCompanions(
                input, in: parent, nextTo: parentURL,
                lease: lease, hooks: hooks
            )
            let primary = try stagePrimary(input.bytes, in: parent, prefix: prefix, protection: protection)
            try primary.publishing(retireOnFailure: retirement(
                using: journal, parent: parent, primary: input.url.lastPathComponent, scratch: primary.name,
                protection: protection
            )) {
                hooks.afterPrimaryStaged?()
                try journal?.begin(
                    priorDigest: priorDigest, desired: Data(SHA256.hash(data: input.bytes)), name: primary.name,
                    receipt: ExportOwnedFileReceipt(bytes: input.bytes, stamp: primary.stamp)
                )
                try authorization.checkRecoveryObject(primary.stamp)
                hooks.beforePromotion?()
                try promote(primary, input: input, authorization: authorization, companions: staged, lease: lease)
            }
            let diagnostics = finish(journal, parent: parent, hooks: hooks, diagnostics: input.diagnostics)
            return ExportResult(
                primaryFile: input.url,
                companionFiles: staged?.urls ?? [],
                diagnostics: diagnostics
            )
        }
    }
}

private extension ExportFilePublication {
    private static func reconcile(_ journal: ExportJournalStore?, for url: URL, in parent: DirectoryHandle,
                                  protection: ExportRecoveryProtection) throws -> Data? {
        guard let journal else { return nil }
        try ExportPrimaryRecovery.recover(journal, primary: url.lastPathComponent, in: parent.descriptor,
                                          protection: protection)
        return try ExportPrimaryRecovery.digest(of: url.lastPathComponent, in: parent.descriptor)
    }

    private static func retirement(using journal: ExportJournalStore?, parent: DirectoryHandle,
                                   primary: String, scratch: String,
                                   protection: ExportRecoveryProtection) -> (() throws -> Void)? {
        journal.map { journal in
            {
                guard journal.record.pending != nil
                else { throw Filesystem.recoveryRequired(directory: parent.descriptor, name: scratch) }
                try ExportPrimaryRecovery.recover(
                    journal,
                    primary: primary,
                    in: parent.descriptor,
                    protection: protection
                )
            }
        }
    }

    private static func openJournal(_ location: ExportRecoveryLocation, parent: Stamp,
                                    leaf: String) throws -> ExportJournalStore {
        do { return try ExportJournalStore(location: location, parent: parent, leaf: leaf) } catch {
            throw ExportError.recoveryStorageUnavailable(location.directory)
        }
    }

    private static func promote(_ primary: StagedPrimary, input: HTMLFilePublicationInput,
                                authorization: ExportDestinationAdmission, companions: StagedCompanions?,
                                lease: ExportLifetimeLease) throws {
        try lease.withPublicationCutoff {
            try verify(input, parent: authorization.parent, parentPath: input.url.deletingLastPathComponent().path,
                       parentStamp: authorization.parentStamp, staged: companions)
            try authorization.checkTarget(input.url)
            try authorization.checkRecoveryObject(primary.stamp)
            guard try Filesystem.primaryBaseline(input.url.lastPathComponent, in: authorization.parent.descriptor)
                == authorization.primaryStamp,
                try Filesystem.childStamp(primary.name, in: authorization.parent.descriptor) == primary.stamp
            else { throw ExportError.unsafePublication }
            try primary.promote(as: input.url.lastPathComponent, absent: authorization.primaryStamp == nil)
        }
    }

    private static func finish(_ journal: ExportJournalStore?, parent: DirectoryHandle, hooks: ExportPublicationHooks,
                               diagnostics: [ExportDiagnostic]) -> [ExportDiagnostic] {
        guard let journal else { return diagnostics }
        do {
            // Once rename succeeds, sync/finalization failure cannot undo the
            // saved output or turn it into a misleading publication failure.
            guard fsync(parent.descriptor) == 0 else { throw Filesystem.posixFailure() }
            try hooks.beforeJournalFinalization?()
            try journal.finish()
            return diagnostics
        } catch {
            let warning = ExportDiagnostic(severity: .warning, message: String(
                localized: """
                The export was saved, but its recovery record could not be finalized. \
                Keep the output and try this destination again.
                """,
                bundle: .module
            ))
            return diagnostics + [warning]
        }
    }

    private static func validate(_ input: HTMLFilePublicationInput) throws {
        guard input.url.isFileURL, safeName(input.url.lastPathComponent), safeName(input.assetsDirectoryName),
              input.assetsDirectoryName.utf8.elementsEqual(ExportHTMLWriter.assetsDirectoryName(for: input.url).utf8)
        else { throw ExportError.unsafePublication }
        if case .standalone = input.mode, !input.resources.isEmpty,
           input.url.pathExtension.lowercased() == "assets" {
            throw ExportError.unsafePublication
        }
        guard input.bytes.count <= ExportResourceBudget.maxFinalHTMLUTF8Bytes,
              input.resources.count <= ExportResourceBudget.standard.maxResourceCount
        else { throw BoundedExportHTML.tooLarge }
        var bytes = 0
        for resource in input.resources {
            try Task.checkCancellation()
            guard resource.bytes.count <= ExportResourceBudget.standard.maxSingleResourceBytes,
                  bytes <= ExportResourceBudget.standard.maxAggregateResourceBytes - resource.bytes.count
            else { throw BoundedExportHTML.tooLarge }
            bytes += resource.bytes.count
            guard resource.identity == ExportResourceIdentity(
                bytes: resource.bytes,
                mimeType: resource.identity.mimeType
            ),
                safeName(resource.identity.fileName) else { throw ExportError.unsafePublication }
        }
    }

    private static func stageCompanions(
        _ input: HTMLFilePublicationInput,
        in parent: DirectoryHandle, nextTo parentURL: URL,
        lease: ExportLifetimeLease, hooks: ExportPublicationHooks
    ) throws -> StagedCompanions? {
        if case .selfContained = input.mode {
            return nil
        }
        guard !input.resources.isEmpty else { return nil }
        let assetsName = input.assetsDirectoryName
        let created = mkdirat(parent.descriptor, assetsName, mode_t(S_IRUSR | S_IWUSR | S_IXUSR)) == 0
        if !created, errno != EEXIST {
            throw Filesystem.posixFailure()
        }
        let descriptor = openat(parent.descriptor, assetsName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.unsafePublication }
        let directory = DirectoryHandle(descriptor)
        let stamp = try Filesystem.directoryStamp(descriptor)
        hooks.afterCompanionDirectoryOpened?()
        guard try Filesystem.directoryAtPath(parentURL.path, matches: Filesystem.directoryStamp(parent.descriptor)),
              try Filesystem.childDirectory(assetsName, in: parent.descriptor, matches: stamp)
        else { throw ExportError.unsafePublication }
        let assetsURL = parentURL.appendingPathComponent(assetsName, isDirectory: true)
        let marker = ExportFileWriter.markerFileName
        let owner = try ExportAssetOwnerMarker.bytes(primary: input.url.lastPathComponent, assets: assetsName)
        let markerStamp: Stamp
        if created {
            markerStamp = try stage(owner, named: marker, in: descriptor)
        } else {
            guard let existing = try Filesystem.existingBytes(owner, named: marker, in: descriptor)
            else { throw ExportError.unsafePublication }
            markerStamp = existing
        }
        var entries = [(name: marker, stamp: markerStamp)]
        var urls = [assetsURL.appendingPathComponent(marker)]
        var retained = try ExportPublicationRetention.scanAssets(descriptor, limits: hooks.retentionLimit)
        for resource in input.resources {
            try Task.checkCancellation()
            try lease.checkActive()
            guard try Filesystem.childDirectory(assetsName, in: parent.descriptor, matches: stamp)
            else { throw ExportError.unsafePublication }
            let name = resource.identity.fileName
            try retained.reserve(name: name, bytes: resource.bytes.count, limits: hooks.retentionLimit)
            try entries.append((name, stage(resource.bytes, named: name, in: descriptor)))
            urls.append(assetsURL.appendingPathComponent(name))
        }
        return StagedCompanions(directory: directory, stamp: stamp, entries: entries, urls: urls)
    }

    private static func verify(
        _ input: HTMLFilePublicationInput, parent: DirectoryHandle,
        parentPath: String, parentStamp: Stamp, staged: StagedCompanions?
    ) throws {
        guard try Filesystem.directoryAtPath(parentPath, matches: parentStamp)
        else { throw ExportError.unsafePublication }
        guard let staged else { return }
        guard try Filesystem.childDirectory(input.assetsDirectoryName, in: parent.descriptor, matches: staged.stamp)
        else { throw ExportError.unsafePublication }
        for entry in staged.entries {
            guard try Filesystem.childStamp(entry.name, in: staged.directory.descriptor) == entry.stamp
            else { throw ExportError.unsafePublication }
        }
    }

    private static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.utf8.contains(UInt8(ascii: "/")) && !name.utf8.contains(0)
    }
}

private extension ExportFilePublication {
    /// Existing names are opened without following links and compared by bytes.
    /// New names are linked from an exclusive temporary inode, never renamed
    /// over a resource used by the previous primary.
    private static func stage(_ bytes: Data, named name: String, in directory: Int32) throws -> Stamp {
        if let existing = try Filesystem.existingBytes(bytes, named: name, in: directory) {
            return existing
        }
        let temporary = ".mt-\(UUID().uuidString).stage"
        try Filesystem.withScratch(bytes, name: temporary, in: directory, retainOnSuccess: false) { _, _ in
            if linkat(directory, temporary, directory, name, 0) != 0, errno != EEXIST {
                throw Filesystem.posixFailure()
            }
        }
        guard let installed = try Filesystem.existingBytes(bytes, named: name, in: directory)
        else { throw ExportError.unsafePublication }
        return installed
    }

    private static func stagePrimary(_ bytes: Data, in directory: DirectoryHandle,
                                     prefix: String, protection: ExportRecoveryProtection) throws -> StagedPrimary {
        let temporary = prefix + UUID().uuidString + ".html.tmp"
        return try Filesystem
            .withScratch(bytes, name: temporary, in: directory.descriptor, retainOnSuccess: true) { _, stamp in
                StagedPrimary(directory: directory, name: temporary, stamp: stamp, bytes: bytes, protection: protection)
            }
    }
}

/// Compatibility name for the optional validated entry point.
typealias ValidatedFilePublication = ExportFilePublication
