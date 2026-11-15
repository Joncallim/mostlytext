import FileCore

extension ExternalFileController {
    /// A failed write still needs a retry when its exact dirty document is retained in an inactive tab.
    func isRetainedRecoveryPersist(_ document: FileDocument, generation: UInt) -> Bool {
        guard !disposed, lifecycleGeneration == generation, let model else { return false }
        return model.tabStore.tabs.contains { tab in
            let live = tab.document
            return live.id == document.id && live.recoveryEpoch == document.recoveryEpoch
                && live.mutationGeneration == document.mutationGeneration
                && live.text.isExactlyEqual(to: document.text) && live.state != .clean
        }
    }

    func matchesRecoveryPersistRetry(_ document: FileDocument, generation: UInt) -> Bool {
        guard case let .persist(retry, retryGeneration)? = recoveryRetryAction else { return false }
        return retryGeneration == generation && retry.id == document.id
            && retry.recoveryEpoch == document.recoveryEpoch
            && retry.mutationGeneration == document.mutationGeneration
            && retry.text.isExactlyEqual(to: document.text)
    }
}
