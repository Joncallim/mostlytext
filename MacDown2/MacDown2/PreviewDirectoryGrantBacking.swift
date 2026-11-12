import Foundation
import LocalResourceAccess

/// The production path uses URL's security scope. A per-acquisition test driver can count actual
/// start/stop calls through every owner transition without requiring an interactive folder panel.
struct PreviewDirectoryScopeAccess: Sendable {
    let start: @MainActor @Sendable (URL) -> Bool
    let stop: @MainActor @Sendable (URL) -> Void

    static let system = PreviewDirectoryScopeAccess(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

/// Pins a document's resource directory and retains its access scope until every admitted use drains.
/// A backing cannot be retargeted. Explicit panel selections and the active HTML preview's automatic
/// document-directory access have distinct factories; neither can borrow the other's authority.
final class PreviewDirectoryGrantBacking: @unchecked Sendable {
    private struct OpenedDirectory: Sendable {
        let root: DirectoryLease
        let document: DirectoryLease
    }

    private struct State {
        var revoked = false
        var users = 0
        var closed = false
    }

    final class Use: @unchecked Sendable {
        let documentDirectory: DirectoryLease
        private let backing: PreviewDirectoryGrantBacking

        fileprivate init(backing: PreviewDirectoryGrantBacking) {
            self.backing = backing
            documentDirectory = backing.documentDirectory
        }

        deinit { backing.finishUse() }
    }

    let documentEpoch: UUID
    let requestedDocumentURL: URL
    private let scopeURL: URL
    private let scopeStarted: Bool
    private let scopeAccess: PreviewDirectoryScopeAccess
    private let rootDirectory: DirectoryLease
    private let documentDirectory: DirectoryLease
    private let lock = NSLock()
    private var state = State()

    private init(documentURL: URL, scopeURL: URL, epoch: UUID,
                 scopeStarted: Bool, scopeAccess: PreviewDirectoryScopeAccess,
                 opened: OpenedDirectory) {
        documentEpoch = epoch
        requestedDocumentURL = documentURL
        self.scopeURL = scopeURL
        self.scopeStarted = scopeStarted
        self.scopeAccess = scopeAccess
        rootDirectory = opened.root
        documentDirectory = opened.document
    }

    /// The panel receipt records the object selected by the user. The opened descriptor must identify that same
    /// object, and child acquisition must stay beneath it. The worker does filesystem operations off MainActor.
    @MainActor
    static func acquire(
        selection: PreviewResourceFolderSelection,
        currentDocumentURL: URL,
        epoch: UUID,
        scopeAccess: PreviewDirectoryScopeAccess = .system
    ) async throws -> PreviewDirectoryGrantBacking {
        guard selection.requestedDocumentURL == currentDocumentURL else {
            throw ResourceReadError.changedRoot
        }
        let scopeStarted = scopeAccess.start(selection.selectedFolderURL)
        do {
            let opened = try await Task.detached(priority: .utility) {
                try openDocumentDirectory(selection: selection)
            }.value
            guard !Task.isCancelled else {
                close(opened)
                throw ResourceReadError.cancelled
            }
            return PreviewDirectoryGrantBacking(
                documentURL: currentDocumentURL, scopeURL: selection.selectedFolderURL,
                epoch: epoch, scopeStarted: scopeStarted, scopeAccess: scopeAccess, opened: opened
            )
        } catch {
            if scopeStarted {
                scopeAccess.stop(selection.selectedFolderURL)
            }
            throw error
        }
    }

    /// The active HTML preview already has automatic access to the saved document's parent. Pin that exact
    /// directory before WebKit loads the saved revision, without manufacturing an explicit panel selection.
    /// This one directory-open operation has the same MainActor timing as the former active scheme handler;
    /// individual resource reads run on PreviewResourceAdmission's detached workers.
    @MainActor
    static func acquireAutomatic(
        documentURL: URL, epoch: UUID,
        scopeAccess: PreviewDirectoryScopeAccess = .system
    ) throws -> PreviewDirectoryGrantBacking {
        let directoryURL = documentURL.deletingLastPathComponent()
        let scopeStarted = scopeAccess.start(directoryURL)
        do {
            let root = try DirectoryLease(opening: directoryURL)
            return PreviewDirectoryGrantBacking(
                documentURL: documentURL, scopeURL: directoryURL, epoch: epoch,
                scopeStarted: scopeStarted, scopeAccess: scopeAccess,
                opened: OpenedDirectory(root: root, document: root)
            )
        } catch {
            if scopeStarted {
                scopeAccess.stop(directoryURL)
            }
            throw error
        }
    }

    /// Admission is separate from UI delivery. The caller's worker retains `Use` until real I/O ends; revocation
    /// prevents new uses immediately and leaves existing descriptors/scope alive until their last use is dropped.
    func acquireUse() -> Use? {
        let admitted = lock.withLock { () -> Bool in
            guard !state.revoked else { return false }
            state.users += 1
            return true
        }
        return admitted ? Use(backing: self) : nil
    }

    func revoke() {
        let shouldClose = lock.withLock { () -> Bool in
            state.revoked = true
            guard state.users == 0, !state.closed else { return false }
            state.closed = true
            return true
        }
        if shouldClose {
            closeResources()
        }
    }

    private func finishUse() {
        let shouldClose = lock.withLock { () -> Bool in
            precondition(state.users > 0)
            state.users -= 1
            guard state.revoked, state.users == 0, !state.closed else { return false }
            state.closed = true
            return true
        }
        if shouldClose {
            closeResources()
        }
    }

    private func closeResources() {
        documentDirectory.close()
        if documentDirectory !== rootDirectory {
            rootDirectory.close()
        }
        if scopeStarted {
            let url = scopeURL
            let access = scopeAccess
            Task { @MainActor in access.stop(url) }
        }
    }

    deinit { revoke() }

    private static func close(_ opened: OpenedDirectory) {
        opened.document.close()
        if opened.document !== opened.root {
            opened.root.close()
        }
    }

    private static func openDocumentDirectory(
        selection: PreviewResourceFolderSelection
    ) throws -> OpenedDirectory {
        let selectedComponents = selection.selectedFolderURL.resolvingSymlinksInPath()
            .standardizedFileURL.pathComponents
        let parentComponents = selection.requestedDocumentURL.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard parentComponents.starts(with: selectedComponents) else { throw ResourceReadError.denied }

        let root = try DirectoryLease(opening: selection.selectedFolderURL)
        guard root.identity.device == selection.selectedDevice,
              root.identity.inode == selection.selectedInode
        else {
            root.close()
            throw ResourceReadError.changedRoot
        }
        let childComponents = Array(parentComponents.dropFirst(selectedComponents.count))
        guard !childComponents.isEmpty else { return OpenedDirectory(root: root, document: root) }
        do {
            let child = try root.childDirectory(ResourceReference(components: childComponents))
            return OpenedDirectory(root: root, document: child)
        } catch {
            root.close()
            throw error
        }
    }
}
