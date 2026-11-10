import Foundation
import UniformTypeIdentifiers

/// Represents an open document and its lifecycle state.
///
/// `FileDocument` is a value type: mutating the state machine returns a new
/// instance, keeping the core pure and synchronous. IO is performed at the
/// edges by `FileStore` and `RecoveryBuffer`, which are injected so tests can
/// substitute them.
public struct FileDocument: Sendable {
    /// A stable identifier. For saved files this is the file URL's absolute
    /// string; for untitled documents it is a generated UUID.
    public private(set) var id: String

    /// The URL of the file on disk, or `nil` for untitled documents.
    public var fileURL: URL?

    /// The current text content of the document.
    public var text: String

    /// The format associated with this document.
    public private(set) var format: FileFormat

    /// The encoding metadata carried with this document's text. Set from the
    /// byte snapshot on load, preserved through edits and Save As, and only
    /// replaced by an accepted external snapshot or an explicit override.
    public private(set) var encoding: FileEncodingMetadata

    /// The current lifecycle state.
    public var state: FileDocumentState

    public private(set) var lastKnownRevision: FileRevision?

    /// The content hash this document's unsaved text was written against, when the file
    /// was missing at session restore and so no revision could be read. It keeps the
    /// baseline alive across another relaunch: if the file reappears with different
    /// content, restore then reports a conflict instead of treating the new disk content
    /// as the baseline (and letting the first save overwrite it).
    public internal(set) var restoredBaseSHA256: String?

    public private(set) var pendingExternalRevision: FileRevision?
    public private(set) var backingState: FileBackingState

    /// Monotonically advances for every visible document-state transition.
    /// Async callers use this to reject ABA-shaped stale completions where the
    /// text and state happen to return to their original values.
    public private(set) var mutationGeneration: UInt

    public var lastKnownModificationDate: Date? {
        lastKnownRevision?.modificationDate
    }

    /// The store used for disk IO. Injected to allow test doubles.
    public let fileStore: FileStore

    /// The recovery buffer used for autosave/recovery of untitled documents.
    /// Injected to allow tests to use an isolated directory.
    public let recoveryBuffer: RecoveryBuffer
    /// Distinguishes separate lifetimes that reuse the same URL-derived ID.
    /// Globally unique recovery lifetime, persisted with the session. Unlike a
    /// process-local counter it cannot collide after relaunch.
    public private(set) var recoveryEpoch: UUID

    /// Creates a new document, optionally backed by an existing file.
    public init(
        fileURL: URL? = nil,
        text: String = "",
        format: FileFormat? = nil,
        encoding: FileEncodingMetadata = .utf8Default,
        fileStore: FileStore = FileStore(),
        recoveryBuffer: RecoveryBuffer = .shared,
        documentID: String? = nil,
        recoveryEpoch: UUID? = nil
    ) {
        let normalizedURL = fileURL?.standardizedFileURL
        self.fileURL = normalizedURL
        self.text = text
        self.encoding = encoding
        self.fileStore = fileStore
        self.recoveryBuffer = recoveryBuffer
        // Compatibility construction remains synchronous for pure state
        // tests and legacy callers. Production creation uses `create`, which
        // obtains a managed epoch from `RecoveryBuffer` after loading its
        // durable high-water ledger.
        self.recoveryEpoch = recoveryEpoch ?? UUID()
        state = .clean
        backingState = normalizedURL == nil ? .untitled : .available
        lastKnownRevision = nil
        pendingExternalRevision = nil
        mutationGeneration = 0

        if let normalizedURL {
            id = normalizedURL.absoluteString
            self.format = format ?? FileFormat.format(for: normalizedURL, in: FileFormatRegistry())
                ?? FileFormatRegistry.defaultFormats.first { $0.id == "plaintext" }
                ?? FileFormat(
                    id: "plaintext", name: FileFormatRegistry.plainTextDisplayName(),
                    utType: .plainText, extensions: ["txt"]
                )
        } else {
            id = documentID ?? UUID().uuidString
            self.format = format ?? FileFormatRegistry.defaultFormats.first { $0.id == "markdown" }
                ?? FileFormat(
                    id: "markdown",
                    name: "Markdown",
                    utType: UTType(filenameExtension: "md") ?? .plainText,
                    extensions: ["md"],
                    highlightLanguageID: "markdown",
                    previewCapability: .markdown,
                    defaultPreviewMode: .rendered,
                    supportedPreviewModes: [.rendered]
                )
        }
    }

    // MARK: - State transitions

    /// Marks the document as clean (used after a successful save or discard).
    public func markClean() -> FileDocument {
        var copy = self
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Begins the close flow for a dirty document, transitioning to prompting.
    public func requestClose() -> (document: FileDocument, resolution: CloseResolution?) {
        var copy = self
        switch state {
        case .clean:
            return (copy, .discard)
        case .dirty:
            copy.state = .promptingClose
            copy.advanceMutation()
            return (copy, nil)
        case .conflict:
            // A conflict has a distinct close flow. Do not erase that fact by
            // converting it to an ordinary dirty-close prompt.
            return (copy, nil)
        case .promptingClose:
            return (copy, nil)
        }
    }

    /// Resolves the close prompt.
    public func resolveClose(_ resolution: CloseResolution) -> FileDocument {
        var copy = self
        switch resolution {
        case .save, .discard:
            copy.state = .clean
        case .cancel:
            // Only a document that was actually prompting to close returns to
            // `.dirty`. Guard against dirtying an already-clean document if
            // `resolveClose(.cancel)` is ever called out of the prompt flow.
            copy.state = (state == .promptingClose) ? .dirty : state
        }
        if copy.state != state {
            copy.advanceMutation()
        }
        return copy
    }

    // MARK: - File IO

    /// Loads content from the document's `fileURL` into a new instance with `text` set.
    public func load() throws(FileStoreError) -> FileDocument {
        guard let fileURL else {
            throw .invalidURL
        }
        let snapshot = try fileStore.readSnapshot(from: fileURL, decoding: encoding.decodingPolicy)
        var copy = self
        copy.text = snapshot.text
        copy.encoding = snapshot.encodingMetadata
        copy.lastKnownRevision = snapshot.revision
        copy.pendingExternalRevision = nil
        copy.backingState = .available
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Saves the current `text` to the document's `fileURL`.
    public func save() throws(FileStoreError) -> FileDocument {
        try saving(expectedRevision: lastKnownRevision)
    }

    /// Saves using a caller-owned baseline. The workspace save serializer uses
    /// this to let a later queued save adopt the revision accepted by an
    /// earlier save without losing edits made in between.
    ///
    /// `encodingOverride` writes the text in a different encoding. The result
    /// carries the override as its metadata only because the write succeeded;
    /// a failure throws and the receiver is unchanged.
    public func saving(
        expectedRevision: FileRevision?,
        encodingOverride: FileEncodingMetadata? = nil
    ) throws(FileStoreError) -> FileDocument {
        guard let fileURL else {
            // Untitled documents are not saved to disk; their recovery buffer
            // is maintained separately by `autosave()`.
            throw .invalidURL
        }

        let destinationEncoding = encodingOverride ?? encoding
        let revision = try fileStore.write(
            text,
            to: fileURL,
            encoding: destinationEncoding.encoding,
            bom: destinationEncoding.bom,
            expectedRevision: expectedRevision
        )
        var copy = self
        copy.encoding = destinationEncoding
        copy.lastKnownRevision = revision
        copy.pendingExternalRevision = nil
        copy.backingState = .available
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Saves the current text to a new URL and updates the document identity.
    /// The source document's encoding/BOM metadata is preserved unless an
    /// explicit `encodingOverride` is supplied.
    /// Saves to a new URL while adopting a caller-prepared recovery lifetime.
    /// Workspace production paths obtain this epoch from `RecoveryBuffer`
    /// before entering the write lane, so the resulting identity participates
    /// in the durable bounded-generation protocol.
    public func saveAs(
        _ url: URL,
        recoveryEpoch: UUID = UUID(),
        encodingOverride: FileEncodingMetadata? = nil,
        destinationBaseline: DestinationBaseline? = nil
    ) throws(FileStoreError) -> FileDocument {
        let destination = url.standardizedFileURL
        // The destination encoding becomes document metadata only after the
        // write below succeeds; an override that fails to encode is never
        // adopted. `encodingOverride ?? encoding` is the documented
        // precedence: explicit destination override first, else source.
        let destinationEncoding = encodingOverride ?? encoding
        let revision = try fileStore.write(
            text,
            to: destination,
            encoding: destinationEncoding.encoding,
            bom: destinationEncoding.bom,
            destinationBaseline: destinationBaseline
        )
        var copy = self
        copy.fileURL = destination
        copy.id = destination.absoluteString
        // A URL-derived recovery key denotes a document lifetime, not just a
        // pathname. Save As starts a fresh lifetime so queued recovery work
        // from the former identity cannot be admitted under the new key.
        copy.recoveryEpoch = recoveryEpoch
        copy.format = Self.format(for: destination)
        copy.encoding = destinationEncoding
        copy.lastKnownRevision = revision
        copy.pendingExternalRevision = nil
        copy.backingState = .available
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    /// Adopts a completed Save As destination without discarding edits made
    /// while that write was in flight. `saved` contributes the newly admitted
    /// URL, format, and disk revision; this descendant contributes the newer
    /// text and remains dirty when it differs from the published text.
    public func rebindingSavedDestination(from saved: FileDocument) -> FileDocument {
        var copy = saved
        copy.text = text
        copy.state = text.isExactlyEqual(to: saved.text) ? .clean : .dirty
        // Preserve the fact that this is a post-save local transition while
        // making it newer than both inputs for recovery ordering.
        copy.mutationGeneration = max(mutationGeneration, saved.mutationGeneration)
        copy.advanceMutation()
        return copy
    }

    /// Re-points a file-backed document after an in-app move or rename.
    /// This intentionally performs no IO; the caller has already completed it.
    public func renamed(to url: URL) -> FileDocument {
        renamed(to: url, recoveryEpoch: UUID())
    }

    /// Re-points a document using a caller-prepared recovery lifetime.
    /// Production rename/move paths use an epoch minted by `RecoveryBuffer`
    /// so a relaunch cannot confuse this identity with a legacy random UUID.
    public func renamed(to url: URL, recoveryEpoch: UUID) -> FileDocument {
        let destination = url.standardizedFileURL
        var copy = self
        copy.fileURL = destination
        copy.id = destination.absoluteString
        // The accepted identity changed. Give recovery writes for this
        // lifetime a new epoch before the controller migrates the buffer.
        copy.recoveryEpoch = recoveryEpoch
        copy.format = Self.format(for: destination)
        if let revision = copy.lastKnownRevision {
            copy.lastKnownRevision = FileRevision(
                url: destination,
                modificationDate: revision.modificationDate,
                fileSize: revision.fileSize,
                fileObjectID: revision.fileObjectID,
                sha256: revision.sha256
            )
        }
        copy.advanceMutation()
        return copy
    }

    /// Restores a document's original visible identity after a multi-document
    /// recovery migration fails. The recovery lifetime must change because the
    /// failed batch has already durably retired the original lifetime; the URL,
    /// document ID, text, and user-visible state remain unchanged.
    public func withReplacementRecoveryLifetime(_ epoch: UUID) -> FileDocument {
        var copy = self
        copy.recoveryEpoch = epoch
        copy.advanceMutation()
        // The reverse migration wrote the recovery record using the renamed
        // descendant's generation. Advance once more so the repaired source
        // lifetime can publish an equal-text session snapshot without being
        // mistaken for that prior write.
        copy.advanceMutation()
        return copy
    }

    /// Keeps the visible identity while replacing a recovery lifetime that was
    /// retired during a failed reverse migration.
    public func withFreshRecoveryLifetime() -> FileDocument {
        withReplacementRecoveryLifetime(UUID())
    }

    // MARK: - Autosave / recovery

    /// Writes a recovery copy if this is an untitled document.
    public func autosave() async {
        guard fileURL == nil else { return }
        _ = try? await recoveryBuffer.saveCurrentLifetime(
            content: text,
            for: id,
            version: mutationGeneration,
            epoch: recoveryEpoch
        )
    }

    /// Loads the recovery copy for an untitled document, if present.
    public func loadRecovery() async -> String? {
        guard fileURL == nil else { return nil }
        return try? await recoveryBuffer.load(for: id, epoch: recoveryEpoch)
    }

    /// Clears the recovery copy (call after a successful save-as or explicit discard).
    public func clearRecovery() async {
        await recoveryBuffer.remove(for: id, version: mutationGeneration, epoch: recoveryEpoch)
    }

    // MARK: - External change detection

    // MARK: - Helpers

    /// Internal mutation seam so the public state remains externally read-only
    /// while pure transitions can stay in their own source file.
    mutating func applyExternalState(
        lastKnownRevision: FileRevision? = nil,
        setLastKnownRevision: Bool = false,
        pendingExternalRevision: FileRevision? = nil,
        setPendingExternalRevision: Bool = false,
        backingState: FileBackingState? = nil,
        encoding: FileEncodingMetadata? = nil,
        setEncoding: Bool = false
    ) {
        if setLastKnownRevision {
            self.lastKnownRevision = lastKnownRevision
        }
        if setPendingExternalRevision {
            self.pendingExternalRevision = pendingExternalRevision
        }
        if let backingState {
            self.backingState = backingState
        }
        if setEncoding, let encoding {
            self.encoding = encoding
        }
    }

    mutating func advanceMutation() {
        mutationGeneration &+= 1
    }
}
