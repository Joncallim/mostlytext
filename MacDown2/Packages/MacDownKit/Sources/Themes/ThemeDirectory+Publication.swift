import Darwin
import Foundation

extension ThemeDirectory {
    func install(_ file: ThemeFile) throws -> ThemePublication {
        let staged = try stage(file.encoded())
        do {
            try hooks.beforeExchange?()
            try checkRoot()
            let status = renameatx_np(
                descriptor,
                staged.name,
                descriptor,
                Self.name(for: file.stableID),
                UInt32(RENAME_EXCL)
            )
            guard status == 0 else { throw failure() }
        } catch {
            guard removeOwnedStage(staged) else { throw ThemeStorageError.recoveryRequired(fileName: staged.name) }
            throw error
        }
        return publication(staged)
    }

    func replace(_ file: ThemeFile, expected: ThemeFileFingerprint) throws -> ThemePublication {
        let name = Self.name(for: file.stableID)
        let staged = try stage(file.encoded())
        do {
            guard try read(name).fingerprint == expected else { throw ThemeStorageError.staleFile }
            try hooks.beforeExchange?()
            try checkRoot()
            guard renameatx_np(descriptor, staged.name, descriptor, name, UInt32(RENAME_SWAP)) == 0 else {
                throw failure()
            }
        } catch {
            guard removeOwnedStage(staged) else { throw ThemeStorageError.recoveryRequired(fileName: staged.name) }
            throw error
        }
        // The temporary path now belongs to the displaced destination. Never
        // let ordinary stage cleanup delete it without checking its baseline.
        do {
            try hooks.afterExchange?()
            guard try read(staged.name).fingerprint.matchesMovedObject(expected) else {
                throw ThemeStorageError.staleFile
            }
        } catch {
            guard rollback(staged, destination: name) else {
                throw ThemeStorageError.recoveryRequired(fileName: staged.name)
            }
            throw error
        }
        let removed = unlinkat(descriptor, staged.name, 0) == 0
        return publication(staged, preserved: removed ? nil : staged.name)
    }

    private func rollback(_ staged: StagedFile, destination: String) -> Bool {
        do {
            guard try read(destination).fingerprint.matchesMovedObject(staged.stored.fingerprint) else { return false }
            try hooks.beforeRollback?()
            guard renameatx_np(descriptor, staged.name, descriptor, destination, UInt32(RENAME_SWAP)) == 0 else {
                return false
            }
            // A writer can win after the pre-swap check. Its version is now at
            // the temporary path; preserve it instead of deleting it as ours.
            return removeOwnedStage(staged)
        } catch { return false }
    }

    func delete(id: UUID, expected: ThemeFileFingerprint) throws -> (durabilityWarning: Bool, preservedName: String?) {
        let name = Self.name(for: id)
        guard try read(name).fingerprint == expected else { throw ThemeStorageError.staleFile }
        let tombstone = ".delete-" + UUID().uuidString.lowercased() + ".tmp"
        try hooks.beforeExchange?()
        try checkRoot()
        guard renameatx_np(descriptor, name, descriptor, tombstone, UInt32(RENAME_EXCL)) == 0 else { throw failure() }
        do {
            guard try read(tombstone).fingerprint.matchesMovedObject(expected)
            else { throw ThemeStorageError.staleFile }
        } catch {
            // Exclusive restoration cannot overwrite a new theme at the name.
            guard renameatx_np(descriptor, tombstone, descriptor, name, UInt32(RENAME_EXCL)) == 0 else {
                throw ThemeStorageError.recoveryRequired(fileName: tombstone)
            }
            throw error
        }
        let removed = unlinkat(descriptor, tombstone, 0) == 0
        return (flush(descriptor) != 0, removed ? nil : tombstone)
    }
}
