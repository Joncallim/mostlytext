import Foundation

public extension RecoveryBuffer {
    /// A stale version can make ordinary removal return `alreadyAbsent` while a newer
    /// recovery file remains. Reload must not publish clean state in that case.
    func removeForExternalReload(
        for documentID: String, version: UInt, epoch: UUID
    ) -> RecoveryCleanupResult {
        let outcome = removeWithOutcome(for: documentID, version: version, epoch: epoch)
        guard outcome.isAbsent else { return outcome }
        let location = recoveryURL(for: documentID, epoch: epochIdentifier(epoch))
        do {
            _ = try FileManager.default.attributesOfItem(atPath: location.path)
            return .failed(.verificationFailed(location))
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               failure.code == NSFileReadNoSuchFileError || failure.code == NSFileNoSuchFileError {
                return outcome
            }
            return .failed(.verificationFailed(location))
        }
    }
}
