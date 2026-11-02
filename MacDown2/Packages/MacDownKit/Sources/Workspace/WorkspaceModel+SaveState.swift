import FileCore
import Foundation

/// Presentation ownership for one accepted save, independent of a document ID
/// that Save As may replace before its session and recovery work completes.
struct LogicalSaveOperationID: Hashable {
    private let value = UUID()
}

struct SavingDocumentLifetime: Hashable, Sendable {
    let documentID: String
    let recoveryEpoch: UUID

    init(_ document: FileDocument) {
        documentID = document.id
        recoveryEpoch = document.recoveryEpoch
    }
}

@MainActor
extension WorkspaceModel {
    func isBackingUnavailable(_ document: FileDocument) -> Bool {
        if case .unavailable = document.backingState {
            return true
        }
        return false
    }

    func isCurrent(_ document: FileDocument) -> Bool {
        guard let current = tabStore.activeDocument else { return false }
        return current.id == document.id
            && current.recoveryEpoch == document.recoveryEpoch
            && current.fileURL?.standardizedFileURL == document.fileURL?.standardizedFileURL
            && current.text.isExactlyEqual(to: document.text)
            && current.state == document.state
            && current.mutationGeneration == document.mutationGeneration
    }

    /// Like `isCurrent`, but for the document in a specific tab (active or not).
    func isCurrent(_ document: FileDocument, inTab tabID: UUID) -> Bool {
        guard let current = tabStore.tabs.first(where: { $0.id == tabID })?.document else { return false }
        return current.id == document.id
            && current.recoveryEpoch == document.recoveryEpoch
            && current.fileURL?.standardizedFileURL == document.fileURL?.standardizedFileURL
            && current.text.isExactlyEqual(to: document.text)
            && current.state == document.state
            && current.mutationGeneration == document.mutationGeneration
    }

    /// The tab that owns `document`'s lifetime, active or not.
    func owningTabID(of document: FileDocument) -> UUID? {
        tabStore.tabs.first { isSameDocumentLifetime($0.document, document) }?.id
    }

    func isSameDocumentLifetime(_ lhs: FileDocument, _ rhs: FileDocument) -> Bool {
        lhs.id == rhs.id
            && lhs.recoveryEpoch == rhs.recoveryEpoch
            && lhs.fileURL?.standardizedFileURL == rhs.fileURL?.standardizedFileURL
    }

    /// A queued save may be admitted only while the current document still
    /// descends from its captured baseline. Revision lineage, rather than an
    /// incidental mutation count, is the authority: local edits retain their
    /// baseline while external reconciliation replaces it.
    func currentReferencesAcceptedSaveInput(
        _ current: FileRevision?,
        sourceRevision: FileRevision?,
        expectedRevision: FileRevision?
    ) -> Bool {
        current == sourceRevision || current == expectedRevision
    }

    func acceptedSaveLineageCount(for document: FileDocument) async -> Int {
        await documentWriter.lineageCount(for: document)
    }

    func tracksSaveGeneration(for document: FileDocument) -> Bool {
        latestSaveGenerationByDocumentID[document.id] != nil
    }

    /// Each overlapping save owns its own token, including a nested metadata
    /// retry. Only that token may remove its aliases when its work ends.
    func beginSavingIndicator(for document: FileDocument) -> LogicalSaveOperationID {
        let operation = LogicalSaveOperationID()
        activeSaveOperations[operation] = [SavingDocumentLifetime(document)]
        return operation
    }

    /// Attach the destination before publishing it as the active document.
    /// Retain the source alias until this operation's terminal path runs.
    func includeSavingLifetime(_ document: FileDocument, in operation: LogicalSaveOperationID) {
        guard activeSaveOperations[operation] != nil else { return }
        activeSaveOperations[operation]?.insert(SavingDocumentLifetime(document))
    }

    func endSavingIndicator(_ operation: LogicalSaveOperationID) {
        activeSaveOperations[operation] = nil
    }
}
