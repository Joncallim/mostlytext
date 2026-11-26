import Foundation

public enum ExternalReconciliationDisposition: Sendable, Equatable {
    case noChange
    case metadataAdvanced
    case reloaded
    case localNowMatchesDisk
    case conflicted
    case conflictUpdated
    case conflictClearedToDirty
    case backingUnavailable
}

public struct ExternalReconciliation: Sendable {
    public let document: FileDocument
    public let disposition: ExternalReconciliationDisposition

    public init(document: FileDocument, disposition: ExternalReconciliationDisposition) {
        self.document = document
        self.disposition = disposition
    }
}

public extension FileDocument {
    /// The document in conflict with `revision` (the file as it is now): used when
    /// a restored unsaved edit predates an external change to its file.
    ///
    /// `baseSHA256` is the content hash the unsaved text was written against. It becomes the document's
    /// known baseline (a hash-only revision), so the monitor's first probe — which sees the changed disk
    /// bytes — keeps the conflict, and the session keeps recording the real base, instead of adopting the
    /// changed disk as the baseline and letting a Save overwrite it.
    func markingExternalConflict(with revision: FileRevision, baseSHA256: String? = nil) -> FileDocument {
        var copy = self
        copy.state = .conflict
        if let baseSHA256 {
            copy.applyExternalState(
                lastKnownRevision: FileRevision(
                    url: revision.url,
                    modificationDate: nil,
                    fileSize: 0,
                    fileObjectID: nil,
                    sha256: baseSHA256
                ),
                setLastKnownRevision: true
            )
        }
        copy.applyExternalState(
            pendingExternalRevision: revision,
            setPendingExternalRevision: true,
            backingState: .available
        )
        copy.advanceMutation()
        return copy
    }

    func reconcilingExternalSnapshot(_ snapshot: FileSnapshot) -> ExternalReconciliation {
        if snapshot.text.isExactlyEqual(to: text) {
            return reconcilingMatchingExternalText(snapshot)
        }

        // A failed read makes even a clean tab temporarily dirty to protect
        // its recovery copy. That is not an authored edit: if the cached text
        // remains exact, the next readable disk version is authoritative.
        if case .unavailable = backingState,
           let cleanText = unavailableCleanText,
           text.isExactlyEqual(to: cleanText) {
            return ExternalReconciliation(document: reloadedFromExternal(snapshot), disposition: .reloaded)
        }

        // `baselineSHA256` also covers a document restored while its file was missing, which has no revision yet.
        if let baseline = baselineSHA256, snapshot.revision.sha256 == baseline {
            var copy = self
            copy.applyExternalState(
                lastKnownRevision: snapshot.revision,
                setLastKnownRevision: true,
                backingState: .available
            )
            if state == .conflict {
                copy.state = .dirty
                copy.applyExternalState(pendingExternalRevision: nil, setPendingExternalRevision: true)
                copy.advanceMutation()
                return ExternalReconciliation(document: copy, disposition: .conflictClearedToDirty)
            }
            copy.advanceMutation()
            return ExternalReconciliation(document: copy, disposition: .metadataAdvanced)
        }

        var copy = self
        switch state {
        case .clean:
            return ExternalReconciliation(document: reloadedFromExternal(snapshot), disposition: .reloaded)
        case .dirty, .promptingClose:
            copy.state = .conflict
            copy.applyExternalState(
                pendingExternalRevision: snapshot.revision,
                setPendingExternalRevision: true,
                backingState: .available
            )
            copy.advanceMutation()
            return ExternalReconciliation(document: copy, disposition: .conflicted)
        case .conflict:
            copy.applyExternalState(
                pendingExternalRevision: snapshot.revision,
                setPendingExternalRevision: true,
                backingState: .available
            )
            copy.advanceMutation()
            return ExternalReconciliation(document: copy, disposition: .conflictUpdated)
        }
    }

    private func reconcilingMatchingExternalText(_ snapshot: FileSnapshot) -> ExternalReconciliation {
        let backingIsAvailable = if case .available = backingState {
            true
        } else {
            false
        }
        guard state != .clean || lastKnownRevision != snapshot.revision || pendingExternalRevision != nil
            || !backingIsAvailable
        else {
            // Avoid an observable replacement for the normal monitor case:
            // the same stable snapshot has already been reconciled.
            return ExternalReconciliation(document: self, disposition: .noChange)
        }
        var copy = self
        copy.state = .clean
        copy.applyExternalState(
            lastKnownRevision: snapshot.revision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available,
            encoding: snapshot.encodingMetadata,
            setEncoding: true
        )
        copy.advanceMutation()
        return ExternalReconciliation(document: copy, disposition: .localNowMatchesDisk)
    }

    func keepingLocalChanges(acknowledging revision: FileRevision) -> FileDocument {
        var copy = self
        copy.applyExternalState(
            lastKnownRevision: revision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available
        )
        copy.state = .dirty
        copy.advanceMutation()
        return copy
    }

    func reloadedFromExternal(_ snapshot: FileSnapshot) -> FileDocument {
        var copy = self
        copy.text = snapshot.text
        copy.applyExternalState(
            lastKnownRevision: snapshot.revision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available,
            encoding: snapshot.encodingMetadata,
            setEncoding: true
        )
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    func markingBackingUnavailable(_ issue: FileBackingIssue) -> FileDocument {
        var copy = self
        if state == .clean {
            copy.unavailableCleanText = text
        } else if let cleanText = unavailableCleanText,
                  !text.isExactlyEqual(to: cleanText) {
            copy.unavailableCleanText = nil
        }
        copy.applyExternalState(
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .unavailable(issue)
        )
        if state != .dirty {
            copy.state = .dirty
        }
        copy.advanceMutation()
        return copy
    }

    func rebindingExternalMove(to snapshot: FileSnapshot) -> FileDocument {
        // Preserve the old content baseline until the caller reconciles the
        // fresh snapshot. This is what keeps dirty local text safe across a
        // proven rename instead of silently treating the move as a reload.
        renamed(to: snapshot.revision.url)
    }

    /// Merges the baseline accepted by an in-flight save into a later local
    /// edit. The visible text remains the user's newer text and stays dirty,
    /// while the next save is conditional on the revision that was actually
    /// published by the completed write.
    func adoptingSavedBaseline(from saved: FileDocument) -> FileDocument {
        var copy = self
        copy.applyExternalState(
            lastKnownRevision: saved.lastKnownRevision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available,
            encoding: saved.encoding,
            setEncoding: true
        )
        copy.state = .dirty
        copy.advanceMutation()
        return copy
    }
}
