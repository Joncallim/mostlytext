import EditorCore
import FileCore
import Foundation
import Observation
import Workspace

/// Owns live external-file monitoring for one native document window.
///
/// The monitor only emits immutable observations. This main-actor controller
/// is the sole bridge from those observations to the workspace and editor.
@MainActor
@Observable
final class ExternalFileController {
    enum Notice: Equatable {
        case none
        case reloaded
        case moved(URL)
        case conflict
        case unavailable(FileBackingIssue)
        case monitorFailed(String)
        case recoveryCleanup(URL)
    }

    // Internal solely for the same-module persistence extension; the type is
    // app-internal and no public API exposes this state.
    var notice: Notice = .none
    var latestExternalSnapshot: FileSnapshot?

    @ObservationIgnored let monitor: DocumentFileMonitor
    @ObservationIgnored weak var model: WorkspaceModel?
    @ObservationIgnored private let editorStore: EditorTextSystemStore
    @ObservationIgnored private let identity: String
    @ObservationIgnored let recoveryExecutor: any RecoveryActionExecuting
    @ObservationIgnored weak var coordinator: WindowCoordinator?
    @ObservationIgnored weak var owner: WindowController?
    @ObservationIgnored var boundURL: URL?
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    @ObservationIgnored var bindTask: Task<Void, Never>?
    @ObservationIgnored var bindRetryTask: Task<Void, Never>?
    @ObservationIgnored var bindRetryAttempt = 0
    @ObservationIgnored var recoveryTail: Task<Void, Never>?
    @ObservationIgnored var recoveryRetryAction: RecoveryAction?
    @ObservationIgnored var pendingMove: PendingMove?
    @ObservationIgnored var pendingClose: PendingClose?
    @ObservationIgnored var onInitialMoveRecoveryPrepared: (@MainActor () async -> Void)?
    @ObservationIgnored var lifecycleGeneration: UInt = 0
    @ObservationIgnored var disposed = false
    /// Test seam: runs right after the recovery cleanup of a Use-Disk-Version reload returns, before it revalidates.
    @ObservationIgnored var afterUseExternalRecoveryCleanup: (@MainActor () async -> Void)?
    /// Test seam: how a failed watcher bind waits before retrying (production: a real exponential sleep).
    @ObservationIgnored var bindRetrySleep: @MainActor (Duration) async throws
        -> Void = { try await Task.sleep(for: $0) }
    /// Test seam: runs after every monitor observation context has been fully handled (applied or dropped as stale).
    @ObservationIgnored var afterObservationContextHandled: (@MainActor (DocumentFileObservationContext) -> Void)?

    init(
        model: WorkspaceModel,
        editorStore: EditorTextSystemStore,
        identity: String,
        coordinator: WindowCoordinator? = nil,
        monitor: DocumentFileMonitor = DocumentFileMonitor(),
        recoveryExecutor: any RecoveryActionExecuting = DefaultRecoveryActionExecutor()
    ) {
        self.model = model
        self.editorStore = editorStore
        self.identity = identity
        self.coordinator = coordinator
        self.monitor = monitor
        self.recoveryExecutor = recoveryExecutor
    }

    func attach(owner: WindowController) {
        self.owner = owner
    }

    func handle(_ observation: DocumentFileObservation) {
        handle(observation, generation: lifecycleGeneration)
    }

    func handle(_ observation: DocumentFileObservation, generation: UInt) {
        Task { @MainActor [weak self] in
            await self?.apply(observation, generation: generation)
        }
    }

    func handle(_ context: DocumentFileObservationContext) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { afterObservationContextHandled?(context) }
            let currentRequest = await monitor.currentRequestGeneration()
            guard context.bindingGeneration == lifecycleGeneration,
                  context.expectedURL.standardizedFileURL == boundURL?.standardizedFileURL,
                  context.requestGeneration == currentRequest else { return }
            await apply(context.observation, generation: context.bindingGeneration)
        }
    }

    private func apply(_ observation: DocumentFileObservation, generation: UInt) async {
        guard generation == lifecycleGeneration else { return }
        guard !disposed, let model, let document = model.activeDocument else { return }
        // A Save As publishes its destination before the window controller
        // rebinds this watcher. An already queued observation still describes
        // the former URL; never apply it to the new destination during that
        // handoff.
        guard activeDocumentMatchesBoundURL(document) else { return }

        guard await applyObservedFileState(observation, to: document, model: model) else { return }
        if case .monitorFailed = notice {
            notice = .none
        }
    }

    private func applyObservedFileState(
        _ observation: DocumentFileObservation,
        to document: FileDocument,
        model: WorkspaceModel
    ) async -> Bool {
        switch observation {
        case let .available(snapshot):
            guard snapshot.revision.url.standardizedFileURL == boundURL else { return false }
            applyAvailable(snapshot, to: document, model: model)
            return true
        case let .moved(snapshot):
            await applyMove(snapshot, to: document, model: model)
            return true
        case let .missing(url):
            guard url.standardizedFileURL == boundURL else { return false }
            applyUnavailable(.missingOrMoved, to: document, model: model)
            return true
        case let .unavailable(url, issue):
            guard url.standardizedFileURL == boundURL else { return false }
            applyUnavailable(issue, to: document, model: model)
            return true
        }
    }

    func handleMonitorHealth(_ health: DocumentFileMonitorHealth, generation: UInt) {
        guard generation == lifecycleGeneration, !disposed else { return }
        switch health {
        case .healthy:
            if case .monitorFailed = notice {
                notice = .none
            }
        case .failed:
            notice = .monitorFailed("The file watcher stopped. Retry to resume monitoring.")
        }
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        lifecycleGeneration &+= 1
        bindTask?.cancel()
        bindRetryTask?.cancel()
        noticeTask?.cancel()
        noticeTask = nil
        latestExternalSnapshot = nil
        pendingMove = nil
        pendingClose = nil
        boundURL = nil
        bindTask = Task { [monitor] in await monitor.cancel() }
    }

    private func applyAvailable(_ snapshot: FileSnapshot, to document: FileDocument, model: WorkspaceModel) {
        let reconciliation = document.reconcilingExternalSnapshot(snapshot)
        guard reconciliation.disposition != .noChange else { return }
        let replacement = reconciliation.document
        let textChanged = !replacement.text.isExactlyEqual(to: document.text)
        model.tabStore.updateActiveDocument { _ in replacement }
        updateMonitorRevision(from: replacement)

        switch reconciliation.disposition {
        case .reloaded, .localNowMatchesDisk:
            latestExternalSnapshot = nil
            if textChanged {
                replaceEditorText(with: replacement.text)
                showTransient(.reloaded)
            }
            removeRecovery(for: replacement)
        case .conflicted, .conflictUpdated:
            latestExternalSnapshot = snapshot
            persistRecovery(for: replacement)
            noticeTask?.cancel()
            notice = .conflict
        case .conflictClearedToDirty:
            latestExternalSnapshot = nil
            if replacement.state != .conflict, case .conflict = notice {
                notice = .none
            }
        case .metadataAdvanced, .noChange:
            latestExternalSnapshot = nil
            if replacement.state == .clean {
                removeRecovery(for: replacement)
            }
            if replacement.state != .conflict, case .conflict = notice {
                notice = .none
            }
        case .backingUnavailable:
            break
        }
        coordinator?.scheduleSaveSession()
    }

    func applyMove(_ snapshot: FileSnapshot, to document: FileDocument, model: WorkspaceModel) async {
        let context = OperationContext(document: document, generation: lifecycleGeneration)
        if let coordinator, let owner {
            if coordinator.controllerForDocument(url: snapshot.revision.url, excluding: owner) != nil {
                applyUnavailable(.moveCollidesWithOpenDocument, to: document, model: model)
                return
            }
        }

        let rebound: FileDocument
        do {
            rebound = try await document.renamed(
                to: snapshot.revision.url,
                preparedBy: document.recoveryBuffer
            )
        } catch {
            applyUnavailable(.readFailed("Unable to prepare recovery for the moved file."), to: document, model: model)
            return
        }
        let reconciliation = rebound.reconcilingExternalSnapshot(snapshot)
        let replacement = reconciliation.document
        pendingMove = PendingMove(
            context: context,
            source: document,
            replacement: replacement,
            snapshot: snapshot
        )
        // `renamed(to:preparedBy:)` suspended to mint an epoch. Do not use a
        // source snapshot an intervening edit has already superseded.
        guard isCurrent(context, in: model) else {
            pendingMove = nil
            return
        }
        guard await prepareMoveRecovery(from: document, to: replacement) else { return }
        await onInitialMoveRecoveryPrepared?()
        guard isCurrent(context, in: model) else {
            await preserveCurrentDocumentAfterStaleInitialMove(in: model)
            return
        }
        await resumePendingMove()
    }

    func applyUnavailable(_ issue: FileBackingIssue, to document: FileDocument, model: WorkspaceModel) {
        let replacement = document.markingBackingUnavailable(issue)
        model.tabStore.updateActiveDocument { _ in replacement }
        latestExternalSnapshot = nil
        persistRecovery(for: replacement)
        noticeTask?.cancel()
        notice = .unavailable(issue)
        coordinator?.scheduleSaveSession()
    }

    func replaceEditorText(with text: String) {
        guard let system = editorStore.existingSystem(for: identity) else { return }
        system.replaceTextFromExternal(text, preserving: system.viewportSnapshot(), clearUndo: true)
    }
}

extension ExternalFileController {
    struct OperationContext: Sendable {
        let documentID: String
        let fileURL: URL?
        let generation: UInt
        let mutationGeneration: UInt
        let text: String
        let state: FileDocumentState
        let pendingRevision: FileRevision?

        init(document: FileDocument, generation: UInt) {
            documentID = document.id
            fileURL = document.fileURL?.standardizedFileURL
            self.generation = generation
            mutationGeneration = document.mutationGeneration
            text = document.text
            state = document.state
            pendingRevision = document.pendingExternalRevision
        }
    }

    func isBindingCurrent(generation: UInt, url: URL) -> Bool {
        !disposed && lifecycleGeneration == generation && boundURL == url
    }

    private func activeDocumentMatchesBoundURL(_ document: FileDocument) -> Bool {
        document.fileURL?.standardizedFileURL == boundURL
    }

    func isCurrent(_ context: OperationContext, in model: WorkspaceModel) -> Bool {
        guard lifecycleGeneration == context.generation,
              let document = model.activeDocument
        else { return false }
        return document.id == context.documentID
            && document.fileURL?.standardizedFileURL == context.fileURL
            && document.mutationGeneration == context.mutationGeneration
            && document.text.isExactlyEqual(to: context.text)
            && document.state == context.state
            && document.pendingExternalRevision == context.pendingRevision
    }

    func resumePendingMove(after action: RecoveryAction? = nil) async {
        guard let pendingMove,
              let model,
              isCurrent(pendingMove.context, in: model),
              action.map(matchesPendingMoveRetry) ?? true
        else { return }

        self.pendingMove = nil
        let replacement = pendingMove.replacement
        let snapshot = pendingMove.snapshot
        model.tabStore.updateActiveDocument { _ in replacement }
        synchronize(with: replacement)
        coordinator?.remapFolderRootsAfterAcceptedMove(
            from: pendingMove.source.fileURL ?? snapshot.revision.url,
            to: snapshot.revision.url
        )

        if !replacement.text.isExactlyEqual(to: pendingMove.source.text) {
            replaceEditorText(with: replacement.text)
        }
        if replacement.state == .conflict {
            latestExternalSnapshot = snapshot
            noticeTask?.cancel()
            notice = .conflict
        } else {
            latestExternalSnapshot = nil
            showTransient(.moved(snapshot.revision.url))
        }

        // Publish the accepted identity before clearing its migration redirect.
        // If the session write fails, retaining the redirect remains the safe
        // crash-recovery outcome.
        if await model.tabStore.saveSession(), pendingMove.source.state != .clean {
            _ = await pendingMove.source.recoveryBuffer.acknowledgeMigration(
                from: pendingMove.source.id,
                sourceEpoch: pendingMove.source.recoveryEpoch,
                to: replacement.id,
                destinationEpoch: replacement.recoveryEpoch
            )
        }
        coordinator?.scheduleSaveSession()
    }

    func matchesPendingMoveRetry(_ action: RecoveryAction) -> Bool {
        guard let pendingMove else { return false }
        switch action {
        case let .migrate(_, oldID, sourceEpoch, document, ownerID, ownerEpoch, generation):
            return oldID == pendingMove.source.id
                && sourceEpoch == pendingMove.source.recoveryEpoch
                && document.id == pendingMove.replacement.id
                && ownerID == pendingMove.source.id
                && ownerEpoch == pendingMove.source.recoveryEpoch
                && generation == pendingMove.context.generation
        case let .remove(_, id, _, epoch, generation):
            return id == pendingMove.source.id
                && epoch == pendingMove.source.recoveryEpoch
                && generation == pendingMove.context.generation
        case .persist, .retire:
            return false
        }
    }
}
