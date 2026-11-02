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
        let priorFileObjectID = document.lastKnownRevision?.fileObjectID
        let decoding = document.encoding.decodingPolicy
        let expectedURL = fileURL.standardizedFileURL
        let generation = lifecycleGeneration
        Task { @MainActor [weak self] in
            guard let self,
                  isBindingCurrent(generation: generation, url: expectedURL)
            else { return }
            await monitor.updateBaseline(
                priorFileObjectID: priorFileObjectID,
                decoding: decoding,
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
        let priorID = document.lastKnownRevision?.fileObjectID
        let decoding = document.encoding.decodingPolicy
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
            do {
                try await monitor.bind(
                    to: fileURL,
                    priorFileObjectID: priorID,
                    decoding: decoding,
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
