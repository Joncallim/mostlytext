import FileCore
import Foundation
import Workspace

@MainActor
extension ExternalFileController {
    enum ReopenEncodingResult: Equatable {
        case reopened
        /// The user chose to keep their unsaved edits instead of discarding
        /// them for the re-decoded text.
        case declined
        /// The document changed while the file was being read or the
        /// confirmation was up; nothing was replaced.
        case superseded
        /// The requested encoding is the one the document already uses. Nothing
        /// was read, prompted, replaced or cleared (a Reopen is not a Revert).
        case unchanged
        /// No usable backing file, or an unresolved external conflict.
        case unavailable
        /// The file's bytes are not a lossless representation in that
        /// encoding, so no text was produced.
        case unreadable
    }

    // The final origin check adds one branch to the existing disk/conflict state machine.
    // swiftlint:disable cyclomatic_complexity
    /// Re-decodes the active document's file with `encoding`, replacing the
    /// editor text. Adopts exactly the state a "use disk version" resolution
    /// does (baseline, recovery cleanup, undo reset), so the same invariants
    /// apply: dirty text is only replaced after `confirmDiscardingChanges`
    /// answers `true`, and only if the document is still the one that was
    /// asked about.
    func reopenWithEncoding(
        _ encoding: String.Encoding,
        confirmDiscardingChanges: (FileDocument) async -> Bool,
        stillAuthorized: @MainActor () -> Bool = { true }
    ) async -> ReopenEncodingResult {
        guard !disposed, let model, let document = model.activeDocument,
              let url = document.fileURL, document.state != .conflict,
              !model.isSavingActiveDocument
        else { return .unavailable }
        if case .unavailable = document.backingState {
            return .unavailable
        }
        guard document.encoding.encoding != encoding else { return .unchanged }

        let store = document.fileStore
        let snapshot: FileSnapshot
        do {
            snapshot = try await Task.detached(priority: .userInitiated) {
                try store.readSnapshot(from: url, decoding: .explicit(encoding))
            }.value
        } catch {
            return .unreadable
        }

        guard stillAuthorized() else { return .superseded }
        if document.state == .dirty || document.state == .promptingClose {
            guard await confirmDiscardingChanges(document) else { return .declined }
        }
        guard !disposed, stillAuthorized(),
              let current = model.activeDocument,
              current.id == document.id,
              current.recoveryEpoch == document.recoveryEpoch,
              current.mutationGeneration == document.mutationGeneration,
              current.state != .conflict,
              !model.isSavingActiveDocument
        else { return .superseded }

        // The outcome, not the document's revision, says whether the reload landed: after a failed recovery cleanup
        // the untouched document can already carry the snapshot's disk revision.
        switch await applyConflictResolution(.useExternal, snapshot: snapshot, document: current, model: model) {
        case .applied: return .reopened
        case .superseded: return .superseded
        case .cleanupBlocked, .notApplicable: return .unavailable
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
