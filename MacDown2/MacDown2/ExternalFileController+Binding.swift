import FileCore
import Foundation

extension ExternalFileController {
    func start() {
        synchronize(with: model?.activeDocument)
    }

    /// Reinstalls a watcher only after activation or an explicit user retry.
    /// Bounded recovery never devolves into background polling.
    func retryMonitoring() {
        guard !disposed, let document = model?.activeDocument, let url = document.fileURL else { return }
        let generation = lifecycleGeneration
        let standardized = url.standardizedFileURL
        bindRetryTask?.cancel()
        bindTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await monitor.retryWatching()
                guard isBindingCurrent(generation: generation, url: standardized) else { return }
                bindRetryAttempt = 0
                if case .monitorFailed = notice {
                    notice = .none
                }
            } catch {
                guard isBindingCurrent(generation: generation, url: standardized), isCurrentDocument(document) else {
                    return
                }
                notice = .monitorFailed(error.localizedDescription)
            }
        }
    }

    func synchronize(with document: FileDocument?) {
        guard !disposed else { return }

        // Save As can replace an unavailable source with a healthy destination
        // before rebinding its watcher. The old source's warning must not
        // follow the newly published document; a cancelled or failed Save As
        // leaves backingState unavailable and keeps the warning visible.
        if case .unavailable = notice, document?.backingState == .available {
            notice = .none
        }

        if updateExistingBinding(with: document) {
            return
        }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        bindTask?.cancel()
        bindRetryTask?.cancel()
        baselineUpdateSequence &+= 1
        baselineUpdateTask?.cancel()
        baselineUpdateTask = nil
        guard let document, let fileURL = document.fileURL else {
            boundURL = nil
            bindTask = Task { [monitor] in await monitor.cancel() }
            return
        }

        bind(fileURL: fileURL.standardizedFileURL, document: document, generation: generation)
    }

    private func updateExistingBinding(with document: FileDocument?) -> Bool {
        guard let document,
              let fileURL = document.fileURL,
              boundURL == fileURL.standardizedFileURL
        else { return false }
        let expectedURL = fileURL.standardizedFileURL
        let expectedID = document.id
        let generation = lifecycleGeneration
        baselineUpdateSequence &+= 1
        let sequence = baselineUpdateSequence
        baselineUpdateTask?.cancel()
        baselineUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await beforeBaselineUpdate?()
            // Same-URL edits can schedule several independent tasks. Only the
            // newest one may set the monitor's decoding policy or file identity.
            guard !Task.isCancelled,
                  sequence == baselineUpdateSequence,
                  isBindingCurrent(generation: generation, url: expectedURL),
                  let live = model?.activeDocument,
                  live.id == expectedID,
                  live.fileURL?.standardizedFileURL == expectedURL
            else { return }
            await monitor.updateBaseline(
                priorFileObjectID: live.lastKnownRevision?.fileObjectID,
                decoding: live.encoding.decodingPolicy,
                expectedURL: expectedURL
            )
        }
        return true
    }

    private func isCurrentDocument(_ document: FileDocument) -> Bool {
        guard let current = model?.activeDocument else { return false }
        return current.id == document.id && current.mutationGeneration == document.mutationGeneration
    }

    private func bind(fileURL: URL, document: FileDocument, generation: UInt) {
        boundURL = fileURL
        bindTask = Task { [weak self] in
            guard let self else { return }
            // #59 root cause: `monitor.bind(to:...)` below already performs a
            // complete internal reset of its own accord (cancels its pending
            // debounce task and old handles, then bumps its OWN `generation`
            // and `probeSequence` counters exactly once). A separate
            // `monitor.cancel()` call here bumped that SAME internal
            // `generation` counter a second time — `cancel()` bumps it once,
            // `bind()` bumps it again — so `DocumentFileMonitor.generation`
            // ended up permanently one ahead of this controller's own
            // `lifecycleGeneration` (bumped exactly once per `synchronize()`
            // call, in the caller). Every `DocumentFileObservationContext`
            // this monitor ever emits carries that too-high `bindingGeneration`,
            // so `handle(_ context:)`'s `context.bindingGeneration ==
            // lifecycleGeneration` guard failed for every single observation,
            // permanently, for the lifetime of every bound document — not a
            // race, a deterministic off-by-one between two independently
            // incremented counters. Removing this redundant call restores the
            // 1:1 correspondence `handle(_ context:)` depends on.
            guard isBindingCurrent(generation: generation, url: fileURL) else { return }
            await beforeInitialMonitorBind?()
            guard isBindingCurrent(generation: generation, url: fileURL),
                  let live = Self.bindRetryDocument(live: model?.activeDocument, captured: document, url: fileURL)
            else { return }
            do {
                try await monitor.bind(
                    to: fileURL,
                    priorFileObjectID: live.lastKnownRevision?.fileObjectID,
                    decoding: live.encoding.decodingPolicy,
                    onObservation: { _ in },
                    onHealthChange: { [weak self] health in
                        Task { @MainActor [weak self] in
                            self?.handleMonitorHealth(health, generation: generation)
                        }
                    },
                    onContext: { [weak self] context in
                        Task { @MainActor [weak self] in
                            self?.handle(context)
                        }
                    },
                    bindingToken: generation
                )
                guard isBindingCurrent(generation: generation, url: fileURL) else { return }
                // A same-file policy change may have reached updateBaseline
                // before this first bind was installed. Reapply the live
                // baseline after binding so that ordering cannot lose it.
                if let current = Self.bindRetryDocument(
                    live: model?.activeDocument, captured: document, url: fileURL
                ) {
                    await monitor.updateBaseline(
                        priorFileObjectID: current.lastKnownRevision?.fileObjectID,
                        decoding: current.encoding.decodingPolicy,
                        expectedURL: fileURL
                    )
                }
                guard isBindingCurrent(generation: generation, url: fileURL) else { return }
                bindRetryAttempt = 0
                if case .monitorFailed = notice {
                    notice = .none
                }
            } catch {
                guard isBindingCurrent(generation: generation, url: fileURL) else { return }
                notice = .monitorFailed(error.localizedDescription)
                scheduleBindRetry(for: document, generation: generation)
            }
        }
    }
}
