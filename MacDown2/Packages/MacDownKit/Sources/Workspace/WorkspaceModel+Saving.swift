import FileCore
import Foundation

@MainActor
public extension WorkspaceModel {
    /// Result of a Save attempt that is forbidden from presenting a
    /// destination picker. The command palette uses this so its explicit
    /// origin remains authoritative even if the document becomes untitled
    /// or its backing disappears immediately before the save starts.
    enum NonPromptingSaveResult: Sendable, Equatable {
        case handled
        case requiresDestination
    }

    enum SaveDestinationPolicy {
        case promptIfNeeded
        case reportRequirement
    }

    /// Saves the active document. Untitled documents prompt for a location.
    func save() async {
        _ = await save(isRetry: false, destinationPolicy: .promptIfNeeded)
    }

    /// Saves without ever invoking this model's ambient file-panel provider.
    /// Returns `.requiresDestination` when the active document has no usable
    /// backing destination; the caller can then present its own explicitly
    /// scoped Save As UI. The policy is threaded through the metadata-conflict
    /// retry too, so no later re-check can silently fall back to an ambient
    /// panel after the caller chose the non-prompting route.
    func saveWithoutDestinationPrompt() async -> NonPromptingSaveResult {
        await save(isRetry: false, destinationPolicy: .reportRequirement)
    }

    /// Saves the active document to its own file in a different encoding
    /// ("Save with Encoding"). The document's encoding metadata changes only
    /// once the write succeeds: text the encoding cannot hold fails with
    /// `.textNotRepresentable` and leaves both the file and the document as
    /// they were. Never prompts; a document without a usable backing file
    /// reports `.requiresDestination`.
    func saveWithoutDestinationPrompt(encoding: FileEncodingMetadata) async -> NonPromptingSaveResult {
        await save(isRetry: false, destinationPolicy: .reportRequirement, encodingOverride: encoding)
    }

    /// Clears a surfaced error the user has read and chosen to ignore.
    func dismissLastError() {
        lastError = nil
    }

    /// Advisory snapshot of whether a Save *right now* needs a destination.
    /// Useful for validation/tests, but not an atomic routing boundary: a
    /// backing file can disappear immediately after this property is read.
    /// Callers that must guarantee they never prompt ambiently should use
    /// `saveWithoutDestinationPrompt()` instead.
    var requiresDestinationToSave: Bool {
        guard let document = tabStore.activeDocument else { return false }
        return document.fileURL == nil || isBackingUnavailable(document)
    }

    /// - Parameters:
    ///   - isRetry: `true` for the single automatic retry
    ///     `reconcileSaveConflict` makes after a metadata-only external change.
    ///   - destinationPolicy: whether a missing/unavailable destination may
    ///     invoke the model's ambient Save As panel or must be reported back to
    ///     an explicit-origin caller instead.
    func save(
        isRetry: Bool,
        destinationPolicy: SaveDestinationPolicy,
        encodingOverride: FileEncodingMetadata? = nil,
        target: FileDocument? = nil
    ) async -> NonPromptingSaveResult {
        await saveAttempt(
            isRetry: isRetry,
            destinationPolicy: destinationPolicy,
            encodingOverride: encodingOverride,
            target: target,
            continuingOperation: nil
        )
    }

    internal func saveAttempt(
        isRetry: Bool,
        destinationPolicy: SaveDestinationPolicy,
        encodingOverride: FileEncodingMetadata?,
        target: FileDocument?,
        continuingOperation: LogicalSaveOperationID?
    ) async -> NonPromptingSaveResult {
        guard let document = target ?? tabStore.activeDocument else {
            lastError = .noActiveDocument
            return .handled
        }
        if document.state == .conflict {
            lastError = .unresolvedExternalConflict
            return .handled
        }
        if document.fileURL == nil || isBackingUnavailable(document) {
            return await handleMissingSaveDestination(destinationPolicy, continuingOperation: continuingOperation)
        }
        guard inFlightSaveAsByDocumentID[document.id] == nil else { return .handled }

        let context = beginSave(for: document)
        let operation = continuingOperation ?? beginSavingIndicator(for: document)
        if continuingOperation != nil {
            includeSavingLifetime(document, in: operation)
        }
        defer {
            if continuingOperation == nil {
                endSavingIndicator(operation)
            }
        }
        do {
            let result = try await documentWriter.save(document, encodingOverride: encodingOverride)
            result.document.fileURL.map { onDocumentWritten?($0) }
            await applySuccessfulSave(
                result.document,
                originatingFrom: document,
                sourceRevision: result.sourceRevision,
                expectedRevision: result.expectedRevision,
                context: context
            )
            await documentWriter.acknowledge(result)
        } catch {
            if case FileStoreError.fileChangedDuringRead = error {
                return await reconcileSaveConflict(
                    for: document,
                    context: context,
                    retry: SaveConflictRetry(
                        isRetry: isRetry,
                        destinationPolicy: destinationPolicy,
                        encodingOverride: encodingOverride,
                        operation: operation
                    )
                )
            }
            guard shouldSurfaceSaveFailure(for: document, context: context, error: error) else { return .handled }
            lastError = workspaceError(for: error)
        }
        return .handled
    }

    private func handleMissingSaveDestination(
        _ policy: SaveDestinationPolicy,
        continuingOperation: LogicalSaveOperationID?
    ) async -> NonPromptingSaveResult {
        // A retry that lost its destination is no longer writing. Save As
        // starts a separate operation only after the user accepts a location.
        if let continuingOperation {
            endSavingIndicator(continuingOperation)
        }
        if policy == .promptIfNeeded {
            await saveAs()
            return .handled
        }
        return .requiresDestination
    }

    /// Saves the active document to a user-chosen location, prompted via
    /// this model's own `panel` — which resolves against `NSApp.keyWindow`
    /// at presentation time unless the caller bound it to a fixed window.
    /// That is exactly right for the real Save As menu item/shortcut
    /// (invoked *from* the key window), but not for a caller — like the
    /// command palette — that captured a specific origin window earlier
    /// and cannot guarantee it is still key by the time this `await`
    /// resolves. Such a caller should use `saveAs(to:)` instead, having
    /// already presented its own panel explicitly against that window.
    func saveAs() async {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return
        }
        guard let admission = reserveSaveAs(for: document) else { return }
        defer { finishSaveAs(admission) }
        guard let url = await panel.chooseSaveLocation(
            defaultName: Self.defaultSaveAsName(for: document),
            format: document.format
        )
        else { return }
        await saveAs(to: url, expecting: document, admission: admission)
    }

    /// Saves `expected` — the document the caller began Save As *for*,
    /// captured before it presented its panel — to an already-chosen
    /// `url`. The caller owns the panel and its originating window; Workspace
    /// receives only the chosen URL and the expected document.
    /// `expected` is what makes that hand-off safe. A panel stays open for
    /// as long as the user takes to answer it, and the active document can
    /// be replaced (an external-change reload) or switched (another tab
    /// activated) meanwhile — a sheet blocks neither. Saving "whatever is
    /// active now" would write a *different* document's contents to the
    /// filename the user chose for `expected`, and rebind that document to
    /// it. Checking `isCurrent` against a re-read active document would
    /// compare that document with itself and always succeed.
    func saveAs(to url: URL, expecting expected: FileDocument, admission existing: SaveAsAdmission? = nil) async {
        guard isCurrent(expected) else { return }
        let ownsAdmission = existing == nil
        guard let admission = existing ?? reserveSaveAs(for: expected) else { return }
        defer {
            if ownsAdmission {
                finishSaveAs(admission)
            }
        }
        guard ownsSaveAs(admission, for: expected) else { return }
        guard let url = freeDestination(url) else { return }
        // Captured at authorization: publication is conditional on it (#183 F22).
        let baseline: DestinationBaseline?
        do {
            baseline = try await saveAsBaseline(of: expected, at: url)
        } catch {
            lastError = workspaceError(for: error)
            return
        }
        guard documentLifetimeIsOpen(with: expected) else { return }
        await publishSaveAs(expected, to: url, destinationBaseline: baseline, admission: admission)
    }

    /// The filename `saveAs()`'s own panel prompt defaults to — exposed so
    /// a caller presenting its own panel (via `saveAs(to:)`) can offer the
    /// same default without duplicating the fallback-extension logic.
    static func defaultSaveAsName(for document: FileDocument) -> String {
        document.fileURL?.lastPathComponent ?? "Untitled.\(document.format.extensions.first ?? "md")"
    }

    internal func saveInternalForClose() async {
        guard tabStore.activeDocument != nil else { return }
        await save()
    }

    private func publishSaveAs(
        _ document: FileDocument,
        to url: URL,
        destinationBaseline: DestinationBaseline?,
        admission: SaveAsAdmission
    ) async {
        let context = beginSave(for: document)
        inFlightSaveAsByDocumentID[document.id] = context.generation
        let operation = beginSavingIndicator(for: document)
        defer {
            endSavingIndicator(operation)
            if inFlightSaveAsByDocumentID[document.id] == context.generation {
                inFlightSaveAsByDocumentID[document.id] = nil
            }
        }
        do {
            let saved = try await documentWriter.saveAs(document, to: url, destinationBaseline: destinationBaseline)
            onDocumentWritten?(url)
            await applySaveAs(saved, from: document, context: context, progress: (operation, admission))
        } catch {
            guard shouldSurfaceSaveFailure(for: document, context: context, error: error) else { return }
            lastError = workspaceError(for: error)
        }
    }

    private func applySaveAs(
        _ saved: FileDocument,
        from document: FileDocument,
        context: SaveContext,
        progress: (operation: LogicalSaveOperationID, admission: SaveAsAdmission)
    ) async {
        guard let replacement = saveAsReplacement(saved: saved, source: document, context: context) else { return }
        let oldID = document.id
        let recoveryOutcome = await finalizeSaveAsRecovery(replacement, source: document, context: context)
        if case .failed = recoveryOutcome {
            return
        }
        guard let finalReplacement = await prepareSaveAsDestination(
            saved,
            source: document,
            initialReplacement: replacement,
            context: context,
            progress: progress
        ) else { return }
        if case .migrationPending = recoveryOutcome {
            await onSaveAsDestinationSessionPublished?(document, finalReplacement)
            let acknowledged = await document.recoveryBuffer.acknowledgeMigration(
                from: document.id,
                sourceEpoch: document.recoveryEpoch,
                to: finalReplacement.id,
                destinationEpoch: finalReplacement.recoveryEpoch
            )
            guard acknowledged.isAbsent else {
                enqueueSaveAsRetry(
                    .acknowledgeMigration(source: document, destination: finalReplacement),
                    source: document,
                    replacement: finalReplacement,
                    context: context,
                    phase: .retireSource
                )
                lastError = recoveryCleanupError(acknowledged, document: document)
                return
            }
        }
        guard await retireFormerSaveAsSource(document, replacing: finalReplacement) else { return }
        latestSaveGenerationByDocumentID.removeValue(forKey: oldID)
        await documentWriter.retire(document)
        if pendingRecoveryCleanupActions.isEmpty {
            clearLastError(ifUnchangedSince: context.errorRevision)
        }
    }

    private func prepareSaveAsDestination(
        _ saved: FileDocument,
        source document: FileDocument,
        initialReplacement replacement: FileDocument,
        context: SaveContext,
        progress: (operation: LogicalSaveOperationID, admission: SaveAsAdmission)
    ) async -> FileDocument? {
        await onSaveAsRecoveryFinalized?()
        guard let reconciled = saveAsReplacement(saved: saved, source: document, context: context) else { return nil }
        guard await persistReconciledSaveAsRecoveryIfNeeded(reconciled, replacing: replacement) else {
            enqueueSaveAsRetry(
                .persist(for: reconciled),
                source: document,
                replacement: reconciled,
                context: context,
                phase: .publishDestination
            )
            return nil
        }
        guard let finalReplacement = saveAsReplacement(saved: saved, source: document, context: context),
              sameSaveAsSnapshot(finalReplacement, reconciled),
              let tabID = owningTabID(of: document) else { return nil }
        guard includeSaveAsLifetime(finalReplacement, in: progress.admission) else { return nil }
        includeSavingLifetime(finalReplacement, in: progress.operation)
        tabStore.updateDocument(inTab: tabID) { _ in finalReplacement }
        guard await publishSaveAsSession() else {
            enqueueSaveAsRetry(
                .publishSession(for: finalReplacement),
                source: document,
                replacement: finalReplacement,
                context: context,
                phase: .publishDestination
            )
            lastError = .recoveryCleanupRequired(finalReplacement.fileURL ?? URL(fileURLWithPath: finalReplacement.id))
            return nil
        }
        return finalReplacement
    }

    private func applySuccessfulSave(
        _ saved: FileDocument,
        originatingFrom document: FileDocument,
        sourceRevision: FileRevision?,
        expectedRevision: FileRevision?,
        context: SaveContext
    ) async {
        // Apply to the tab that OWNS this document lifetime, active or not: a save that completes after the user
        // switched tabs must still update its own tab's baseline, or the next save of that tab fails its conditional
        // write against the stale baseline and is misreported as an external-change conflict.
        guard let owner = tabStore.tabs.first(where: { isSameDocumentLifetime($0.document, document) }) else { return }
        let tabID = owner.id
        let current = owner.document
        if isCurrent(document, inTab: tabID), isLatestSave(context) {
            tabStore.updateDocument(inTab: tabID) { _ in saved }
            await retireRecoveryAfterCleanSave(saved, context: context)
            return
        }
        guard current.state != .conflict,
              currentReferencesAcceptedSaveInput(
                  current.lastKnownRevision,
                  sourceRevision: sourceRevision,
                  expectedRevision: expectedRevision
              )
        else { return }
        if current.text.isExactlyEqual(to: saved.text), isLatestSave(context) {
            tabStore.updateDocument(inTab: tabID) { _ in saved }
            await retireRecoveryAfterCleanSave(saved, context: context)
            return
        }
        let merged = current.adoptingSavedBaseline(from: saved)
        tabStore.updateDocument(inTab: tabID) { _ in merged }
        guard await merged.persistRecovery() else {
            registerPendingRecovery(.persist(for: merged))
            lastError = .recoveryCleanupRequired(merged.fileURL ?? URL(fileURLWithPath: merged.id))
            return
        }
        if isLatestSave(context) {
            clearLastError(ifUnchangedSince: context.errorRevision)
        }
    }

    /// Removes the recovery entry of a document that was just saved clean, registering a retry if removal fails.
    private func retireRecoveryAfterCleanSave(_ saved: FileDocument, context: SaveContext) async {
        let cleanup = await saved.recoveryBuffer.removeWithOutcome(
            for: saved.id,
            version: saved.mutationGeneration,
            epoch: saved.recoveryEpoch
        )
        if !cleanup.isAbsent {
            registerPendingRecovery(.remove(for: saved))
        }
        publishCleanupResult(cleanup, document: saved, since: context.errorRevision)
    }

    private func beginSave(for document: FileDocument) -> SaveContext {
        nextSaveGeneration &+= 1
        let context = SaveContext(documentID: document.id, generation: nextSaveGeneration, errorRevision: errorRevision)
        latestSaveGenerationByDocumentID[document.id] = context.generation
        return context
    }
}
