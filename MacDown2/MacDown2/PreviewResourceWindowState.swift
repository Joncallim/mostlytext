import FileCore
import Foundation
import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var previewResourceWindowState: PreviewResourceWindowState?
}

/// One native document window owns its folder grant and all preview load tokens. A document change or window close
/// revokes token admission synchronously, before asynchronous worker-ledger cleanup begins.
@MainActor
@Observable
final class PreviewResourceWindowState {
    private struct Attachment {
        let documentID: String
        let recoveryEpoch: UUID
        let documentURL: URL
        let backing: PreviewDirectoryGrantBacking

        func matches(_ document: FileCore.FileDocument) -> Bool {
            document.id == documentID && document.recoveryEpoch == recoveryEpoch
                && document.fileURL == documentURL
        }
    }

    enum Consumer: Hashable {
        case markdown
        case html
    }

    struct SelectionOrigin: Equatable {
        let id: UUID
        let documentID: String
        let recoveryEpoch: UUID
        let documentURL: URL

        func matches(_ document: FileCore.FileDocument) -> Bool {
            document.id == documentID && document.recoveryEpoch == recoveryEpoch
                && document.fileURL == documentURL
        }
    }

    private(set) var revision = UUID()
    private var attachment: Attachment?
    private var contexts: [Consumer: PreviewResourceLoad] = [:]
    private var pendingSelection: SelectionOrigin?
    private(set) var isClosed = false
    private(set) var selectionFailed = false
    @ObservationIgnored private var currentPreviewDocument: (@MainActor () -> (UUID?, FileCore.FileDocument?))?
    /// Test observation after synchronous revocation, still inside the publisher's pre-change callback.
    @ObservationIgnored var afterIdentityInvalidation: (@MainActor () -> Void)?

    isolated deinit {
        // WindowController calls `close()` deterministically; this also protects a future owner that is released
        // without its explicit close path. Synchronous token revocation precedes actor cleanup in either case.
        for context in contexts.values {
            context.revoke()
            Task { await PreviewResourceAdmission.shared.retire(context) }
        }
        attachment?.backing.revoke()
    }

    /// Capture the document lifetime BEFORE showing the panel. Another document, even at the same file URL, may
    /// replace it while the panel is open; that later lifetime cannot inherit this choice.
    func beginSelection(for document: FileCore.FileDocument) -> SelectionOrigin? {
        guard !isClosed, let url = document.fileURL else { return nil }
        let origin = SelectionOrigin(
            id: UUID(), documentID: document.id,
            recoveryEpoch: document.recoveryEpoch, documentURL: url
        )
        pendingSelection = origin
        selectionFailed = false
        return origin
    }

    /// Presentation reads only the existing attachment; it cannot acquire folder authority.
    func hasGrant(for document: FileCore.FileDocument) -> Bool {
        !isClosed && attachment?.matches(document) == true
    }

    func isSelectionCurrent(_ origin: SelectionOrigin, for document: FileCore.FileDocument) -> Bool {
        !isClosed && pendingSelection == origin && origin.matches(document)
    }

    func cancelSelection(_ origin: SelectionOrigin) {
        guard pendingSelection == origin else { return }
        pendingSelection = nil
    }

    func failSelection(_ origin: SelectionOrigin) {
        guard !isClosed, pendingSelection == origin else { return }
        selectionFailed = true
    }

    /// Called after the panel returns. Both its receipt and the document are checked against the pre-panel origin
    /// before and after opening the pinned descriptor; a stale result is revoked, never installed.
    func install(
        _ selection: PreviewResourceFolderSelection,
        from origin: SelectionOrigin,
        currentDocument: @escaping @MainActor () -> FileCore.FileDocument?
    ) async throws {
        guard !isClosed, pendingSelection == origin,
              selection.requestedDocumentURL == origin.documentURL,
              let document = currentDocument(), origin.matches(document), !Task.isCancelled
        else { throw PreviewResourceAdmissionError.revoked }
        let backing = try await PreviewDirectoryGrantBacking.acquire(
            selection: selection, currentDocumentURL: origin.documentURL, epoch: origin.id
        )
        guard !isClosed, pendingSelection == origin,
              let current = currentDocument(), origin.matches(current), !Task.isCancelled
        else {
            backing.revoke()
            throw PreviewResourceAdmissionError.revoked
        }
        revokeCurrent()
        attachment = Attachment(
            documentID: document.id, recoveryEpoch: document.recoveryEpoch,
            documentURL: selection.requestedDocumentURL, backing: backing
        )
        revision = UUID()
    }

    /// Returns a fresh immutable consumer token. Retiring one renderer cannot revoke another renderer's admitted
    /// worker, but replacing this document/window revokes both immediately.
    func beginLoad(for document: FileCore.FileDocument, consumer: Consumer) -> PreviewResourceLoad? {
        retire(consumer)
        guard !isClosed, let attachment, attachment.matches(document) else { return nil }
        let context = PreviewResourceLoad(grant: attachment.backing)
        contexts[consumer] = context
        return context
    }

    func setCurrentPreviewDocument(_ resolver: (@MainActor () -> (UUID?, FileCore.FileDocument?))?) {
        currentPreviewDocument = resolver
    }

    /// Check the live window model, not a SwiftUI task's captured View value, before replacing the current token.
    func beginPreviewLoad(
        for document: FileCore.FileDocument, tabID: UUID,
        sourceGeneration: UInt, grantRevision: UUID, consumer: Consumer
    ) -> PreviewResourceLoad? {
        guard isCurrentPreview(
            document, tabID: tabID, sourceGeneration: sourceGeneration, grantRevision: grantRevision
        ) else { return nil }
        return beginLoad(for: document, consumer: consumer)
    }

    func isCurrentPreview(
        _ document: FileCore.FileDocument, tabID: UUID,
        sourceGeneration: UInt, grantRevision: UUID
    ) -> Bool {
        guard !isClosed, revision == grantRevision,
              let (liveTabID, liveDocument) = currentPreviewDocument?(),
              liveTabID == tabID, let liveDocument,
              liveDocument.id == document.id,
              liveDocument.recoveryEpoch == document.recoveryEpoch,
              liveDocument.fileURL == document.fileURL,
              liveDocument.mutationGeneration == sourceGeneration
        else { return false }
        return true
    }

    func retire(_ consumer: Consumer) {
        guard let context = contexts.removeValue(forKey: consumer) else { return }
        context.revoke()
        Task { await PreviewResourceAdmission.shared.retire(context) }
    }

    /// An old SwiftUI subtree may disappear after its replacement has installed a newer load.
    func retire(_ consumer: Consumer, matching context: PreviewResourceLoad) {
        guard contexts[consumer] === context else { return }
        retire(consumer)
    }

    /// The controller and view lifecycle call this at document identity changes. A matching edit keeps the folder
    /// authority, while its renderer creates a new per-revision load token.
    func reconcile(with document: FileCore.FileDocument?) {
        if let pendingSelection,
           document.map({ pendingSelection.matches($0) }) != true {
            self.pendingSelection = nil
        }
        guard let attachment else { return }
        guard let document, attachment.matches(document) else { revokeCurrent(); return }
    }

    /// The tab store calls this before publishing a different active tab or document identity. It is unconditional:
    /// two tabs can have the same document ID, epoch and URL but cannot share one window's preview authority.
    func invalidateForIdentityChange() {
        guard !isClosed else { return }
        revokeCurrent()
        afterIdentityInvalidation?()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        revokeCurrent()
    }

    private func revokeCurrent() {
        let hadAuthority = pendingSelection != nil || attachment != nil || !contexts.isEmpty
        pendingSelection = nil
        selectionFailed = false
        for consumer in Array(contexts.keys) {
            retire(consumer)
        }
        attachment?.backing.revoke()
        attachment = nil
        if hadAuthority {
            revision = UUID()
        }
    }
}
