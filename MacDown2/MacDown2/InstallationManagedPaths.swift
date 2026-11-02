import AppSettings
import FileCore
import Foundation
import Workspace

/// Relocates only files owned by the development installation. Ordinary
/// authored paths and outside bookmark bytes are never rewritten.
@MainActor
enum InstallationManagedPaths {
    static func relocate(from source: URL, to locations: ApplicationStorageLocations) async throws {
        let store = WorkspaceSessionStore(fileURL: locations.session)
        let snapshot = try store.installationSnapshot()
        guard var session = snapshot.session else { return }
        let recovery = RecoveryBuffer(recoveryDirectory: locations.recovery)
        var changed = false
        for index in session.tabs.indices {
            let original = session.tabs[index]
            if let old = original.fileURL, let new = mapped(old, from: source, to: locations.dataDirectory) {
                try validateOwned(new, beneath: locations.dataDirectory)
                let epoch = original.documentRecoveryEpoch
                if let epoch {
                    await recovery.adoptRecoveryEpoch(epoch)
                }
                let oldContent = try await recovery.load(for: old.absoluteString, epoch: epoch)
                let newContent = try await recovery.load(for: new.absoluteString, epoch: epoch)
                if let content = oldContent ?? newContent {
                    let result = await recovery.migrateWithOutcome(from: old.absoluteString, to: new.absoluteString,
                                                                   content: content, sourceEpoch: epoch,
                                                                   destinationEpoch: epoch)
                    guard result.isComplete else { throw LegacyMigrationFailure.invalidRecord }
                }
                session.tabs[index].fileURL = new
                changed = true
            }
            if let new = try mappedFolder(original, from: source, to: locations.dataDirectory) {
                try validateOwned(new, beneath: locations.dataDirectory)
                session.tabs[index].folderRootAlias = new
                session.tabs[index].folderRootBookmark = try new.bookmarkData(options: .withSecurityScope)
                changed = true
            }
        }
        if changed, !store.publishInstallationSession(session, expecting: snapshot.rawDigest) {
            throw LegacyMigrationFailure.transactionExists
        }
    }

    private static func mappedFolder(_ record: TabRecord, from source: URL, to destination: URL) throws -> URL? {
        if let alias = record.folderRootAlias {
            return mapped(alias, from: source, to: destination)
        }
        guard let bookmark = record.folderRootBookmark else { return nil }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return mapped(resolved, from: source, to: destination)
    }

    static func mapped(_ url: URL, from source: URL, to destination: URL) -> URL? {
        let path = url.standardizedFileURL.pathComponents
        let root = source.standardizedFileURL.pathComponents
        guard url.isFileURL, path.starts(with: root) else { return nil }
        return path.dropFirst(root.count).reduce(destination) { $0.appendingPathComponent($1) }.standardizedFileURL
    }

    static func validateOwned(_ url: URL, beneath root: URL) throws {
        let physical = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let expected = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard physical.starts(with: expected) else { throw LegacyMigrationFailure.unsafeStorage }
    }
}
