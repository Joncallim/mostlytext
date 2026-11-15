import Foundation

// MARK: - Recovery mutation

public extension FileDocument {
    /// Loads the recovery copy for an untitled document, if present.
    func loadRecovery() async -> String? {
        guard fileURL == nil else { return nil }
        return try? await recoveryBuffer.load(for: id, epoch: recoveryEpoch)
    }

    /// A rejected reload may have removed recovery at its proposed version. Reassert the
    /// still-dirty document above that fence without changing its text or disk authority.
    func advancingRecoveryVersion(after removedVersion: UInt) -> FileDocument {
        var copy = self
        copy.advanceRecoveryVersion(after: removedVersion)
        return copy
    }

    /// Returns a new document with `text` updated and the dirty flag set.
    ///
    /// Use this method when replacing text from an external source (e.g.,
    /// recovery-buffer restore) where a no-op change should **not** mark the
    /// document dirty. For user edits, use `edited(text:)` instead.
    func updatingText(_ newText: String) -> FileDocument {
        guard !newText.isExactlyEqual(to: text) else { return self }
        return edited(text: newText)
    }

    /// Persists the current text under the document identity immediately.
    /// Saved documents need this just as much as untitled ones while their
    /// original backing path is unavailable or in conflict.
    ///
    /// Returns `true` when this exact text is durably recorded for this
    /// lifetime, including when another writer (such as the debounced session
    /// save) already recorded the same version first. The buffer refuses to
    /// re-apply a recorded version, so without that check a retry would
    /// report failure for a snapshot that is already safe. A stale version,
    /// different recorded text, or a retired lifetime still fails.
    func persistRecovery() async -> Bool {
        let content = text
        do {
            if try await recoveryBuffer.saveCurrentLifetime(
                content: content,
                for: id,
                version: mutationGeneration,
                epoch: recoveryEpoch
            ) {
                return true
            }
            return try await recoveryBuffer.hasRecordedSnapshot(
                content: content,
                for: id,
                version: mutationGeneration,
                epoch: recoveryEpoch
            )
        } catch {
            return false
        }
    }

    func saveRecovery() async {
        _ = await persistRecovery()
    }
}
