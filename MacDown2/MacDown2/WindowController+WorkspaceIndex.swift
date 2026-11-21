import Foundation
import TextSearch

/// Keeps `workspaceFileIndex` in sync with `fileTreeModel.root` (EPIC-22
/// §6.15, Slice 6a). Split out of `WindowController.swift` for the same
/// reason `WindowController+Close.swift`/`WindowController+TextFilterTasks.swift`
/// are: a distinct, self-contained ownership concern kept in one place.
extension WindowController {
    /// A Quick Open result may be resolved only after this root request's
    /// index has published a ready snapshot for the same access directory.
    /// A root switch clears the publication markers before its first await,
    /// so a panel opened while the new tree/index is still rebuilding has
    /// no actionable origin even if the index still retains old rows.
    var currentQuickOpenOrigin: QuickOpenOrigin? {
        let request = workspaceRootRequestGeneration
        guard !isClosed,
              workspaceTreeRootAppliedGeneration == request,
              lastWorkspaceIndexRefreshGeneration == request,
              let lexicalRoot = fileTreeModel.root,
              fileTreeModel.selectedRootIsCurrent,
              let accessRoot = fileTreeModel.rootAccessURL,
              lastWorkspaceIndexRefreshRoot == accessRoot
        else { return nil }
        return QuickOpenOrigin(generation: request, lexicalRoot: lexicalRoot, accessRoot: accessRoot)
    }

    /// Lets Replace in Folder (Slice 7c) ask the coordinator whether any
    /// window holds unsaved edits for a file it is about to rewrite.
    func installFolderSearchHooks() {
        folderSearchModel.hasUnsavedOpenDocument = { [weak coordinator] url in
            coordinator?.hasUnsavedOpenDocument(at: url) ?? false
        }
        folderSearchModel.fileWasRewritten = { [weak coordinator] url in
            coordinator?.recentFileDocuments.noteWrite(of: url)
        }
        fileTreeModel.onDidMutate = { [weak self] in
            Task { await self?.refreshWorkspaceIndex() }
        }
    }

    /// Re-walks the open folder so Quick Open and Folder Search follow changes
    /// made by this app's own file operations and by other programs (#183
    /// F18). A newer call supersedes an in-flight walk
    /// (`WorkspaceFileIndex.rebuild`), the old snapshot stays queryable until
    /// the new one lands, and no folder (or a closed one) is a no-op.
    ///
    /// `minInterval` lets a frequent trigger (a native tab becoming key) skip a
    /// walk that successfully finished for this root request; file operations always walk.
    func refreshWorkspaceIndex(minInterval: TimeInterval = 0) async {
        let request = workspaceRootRequestGeneration
        guard workspaceTreeRootAppliedGeneration == request,
              let root = fileTreeModel.rootAccessURL
        else { return }
        guard fileTreeModel.selectedRootIsCurrent else {
            stopWorkspaceEvents()
            retireWorkspaceResults()
            return
        }
        if workspaceEventRoot != root {
            stopWorkspaceEvents()
            _ = startWorkspaceEvents(paths: [root.path], root: root, request: request)
        }
        if minInterval > 0, lastWorkspaceIndexRefreshGeneration == request,
           lastWorkspaceIndexRefreshRoot == root,
           let last = lastWorkspaceIndexRefresh, Date().timeIntervalSince(last) < minInterval {
            return
        }
        workspaceIndexBuildGeneration &+= 1
        let build = workspaceIndexBuildGeneration
        guard let indexState = await rebuildWorkspaceIndexWithMonitoring(root: root, request: request, build: build)
        else { return }
        if case .ready = indexState {
            lastWorkspaceIndexRefresh = Date()
            lastWorkspaceIndexRefreshRoot = root
            lastWorkspaceIndexRefreshGeneration = request
        } else if case .building = indexState {
            return
        } else {
            // A failed walk drops the index snapshot. Do not let an older
            // success keep activation inside the throttle window and strand
            // the now-empty index until another forced refresh.
            lastWorkspaceIndexRefresh = nil
            lastWorkspaceIndexRefreshRoot = nil
            lastWorkspaceIndexRefreshGeneration = nil
        }
        if (pendingFolderSearchRootGeneration == request && pendingFolderSearchRoot == root)
            || folderSearchModel.root != root {
            folderSearchModel.setRoot(root, lexicalRoot: fileTreeModel.root)
            pendingFolderSearchRoot = nil
            pendingFolderSearchRootGeneration = nil
        } else {
            folderSearchModel.indexDidRefresh(root: root)
        }
    }

    private func rebuildWorkspaceIndexWithMonitoring(root: URL, request: UInt, build: UInt) async
        -> WorkspaceFileIndex.State? {
        var monitoringRescans = 0
        while true {
            await workspaceFileIndex.rebuild(root: root)
            guard ownsWorkspaceIndexBuild(root: root, request: request, build: build) else { return nil }
            let monitoring = await workspaceFileIndex.monitoringSnapshot()
            guard ownsWorkspaceIndexBuild(root: root, request: request, build: build) else { return nil }
            guard case .ready = monitoring.state else {
                if workspaceEventPaths != [root.path] {
                    stopWorkspaceEvents()
                    _ = startWorkspaceEvents(paths: [root.path], root: root, request: request)
                }
                return monitoring.state
            }
            let paths = [root.path] + monitoring.externalWatchPaths
            guard workspaceEventPaths != paths else { return monitoring.state }
            stopWorkspaceEvents()
            guard startWorkspaceEvents(paths: paths, root: root, request: request) else { return monitoring.state }
            // The target could change after the walk but before the expanded
            // stream starts. Keep old rows inert and scan once under the new
            // coverage before publishing an actionable result.
            retireWorkspaceResults()
            monitoringRescans += 1
            if monitoringRescans < 3 {
                continue
            }
            scheduleWorkspaceMonitoringRetry(root: root, request: request)
            return nil
        }
    }

    private func ownsWorkspaceIndexBuild(root: URL, request: UInt, build: UInt) -> Bool {
        !isClosed && workspaceRootRequestGeneration == request
            && workspaceIndexBuildGeneration == build && fileTreeModel.rootAccessURL == root
    }

    /// Reserve a root request at the user's choice, before an unstructured
    /// task can start out of order. This also retires old search actions in
    /// the dispatch-to-task gap.
    @discardableResult
    func enqueueFileTreeRoot(_ url: URL?, accessURL: URL? = nil) -> Task<Void, Never> {
        let request = beginFileTreeRootRequest()
        let association = model.folderAssociationRevision
        return Task { @MainActor [weak self] in
            guard let self, !isClosed,
                  workspaceRootRequestGeneration == request,
                  model.folderAssociationRevision == association,
                  model.folderURL?.standardizedFileURL == url?.standardizedFileURL
            else { return }
            await applyFileTreeRoot(url, accessURL: accessURL, request: request)
        }
    }

    /// Sets `fileTreeModel`'s root and rebuilds `workspaceFileIndex` to
    /// match it in one step. Deliberately not named `setFolderRoot` —
    /// `WorkspaceModel.setFolderRoot(_:)` is a different, pre-existing
    /// method most call sites already call right next to this one, and
    /// this method needs its own distinct name so the two are never
    /// mistaken for each other. Every call site that changes
    /// `fileTreeModel.root` must go through this method or the queued
    /// `enqueueFileTreeRoot` entry, never `fileTreeModel.setRoot(_:accessURL:)`
    /// directly, so the index can
    /// never silently drift out of sync with the root it is supposed to be
    /// indexing.
    ///
    /// Indexes `fileTreeModel.rootAccessURL` — the real, security-scoped
    /// access URL `setRoot` always establishes once `root` is non-nil — not
    /// the lexical `root` itself, matching `FileTreeModel`'s own
    /// access-scope convention (§2.1) rather than inventing a second one.
    /// A `nil` root (closing the folder) clears the index instead of
    /// rebuilding it, so a stale snapshot from a previously-open folder can
    /// never leak into a later Quick Open query in this same window.
    func setFileTreeRoot(_ url: URL?, accessURL: URL? = nil) async {
        let request = beginFileTreeRootRequest()
        await applyFileTreeRoot(url, accessURL: accessURL, request: request)
    }

    private func beginFileTreeRootRequest() -> UInt {
        stopWorkspaceEvents()
        workspaceRootRequestGeneration &+= 1
        let request = workspaceRootRequestGeneration
        workspaceTreeRootAppliedGeneration = nil
        workspaceIndexBuildGeneration &+= 1
        lastWorkspaceIndexRefresh = nil
        lastWorkspaceIndexRefreshRoot = nil
        lastWorkspaceIndexRefreshGeneration = nil
        pendingFolderSearchRoot = nil
        pendingFolderSearchRootGeneration = nil
        // Before the first suspension: results shown against the old root must
        // never be actionable against the new one (#183 F19).
        coordinator?.closeQuickOpenIfOrigin(self)
        // Every explicit root request replaces the folder access scope, even
        // when the lexical path is unchanged. Retire old results and any
        // Replace run before the first await; neither may borrow new access.
        folderSearchModel.setRoot(nil)
        return request
    }

    private func applyFileTreeRoot(_ url: URL?, accessURL: URL?, request: UInt) async {
        await beforeRootRebuild?()
        guard !isClosed, workspaceRootRequestGeneration == request else { return }
        await fileTreeModel.setRoot(url, accessURL: accessURL)
        guard !isClosed, workspaceRootRequestGeneration == request else { return }
        workspaceTreeRootAppliedGeneration = request
        if let root = fileTreeModel.rootAccessURL {
            _ = startWorkspaceEvents(paths: [root.path], root: root, request: request)
        }
        // Closes Quick Open (Slice 6b) if it's open against this window —
        // an independent hostile review of that slice found the panel's
        // own results/selection could otherwise resolve against a folder
        // root that no longer matches what `fileTreeModel`/
        // `workspaceFileIndex` now point to: `removeController`'s own
        // force-close guard only fires when the WINDOW closes, never when
        // an already-open window's root changes underneath it (Open
        // Folder…/Open Recent Folder/session restore all route through
        // this exact method without ever closing the window), so a stale
        // Quick Open result could resolve `path.relativePath` against the
        // NEW root and silently open the wrong file (or fail silently).
        coordinator?.closeQuickOpenIfOrigin(self)
        guard let indexRoot = fileTreeModel.rootAccessURL else {
            await workspaceFileIndex.clear()
            guard !isClosed, workspaceRootRequestGeneration == request else { return }
            folderSearchModel.setRoot(nil)
            return
        }
        pendingFolderSearchRoot = indexRoot
        pendingFolderSearchRootGeneration = request
        workspaceIndexBuildGeneration &+= 1
        let build = workspaceIndexBuildGeneration
        await workspaceFileIndex.rebuild(root: indexRoot)
        guard !isClosed, workspaceRootRequestGeneration == request,
              workspaceIndexBuildGeneration == build,
              fileTreeModel.rootAccessURL == indexRoot
        else { return }
        let indexState = await workspaceFileIndex.state
        guard !isClosed, workspaceRootRequestGeneration == request,
              workspaceIndexBuildGeneration == build,
              fileTreeModel.rootAccessURL == indexRoot
        else { return }
        if case .ready = indexState {
            lastWorkspaceIndexRefresh = Date()
            lastWorkspaceIndexRefreshRoot = indexRoot
            lastWorkspaceIndexRefreshGeneration = request
        } else if case .building = indexState {
            // A same-root activation refresh can supersede this initial
            // rebuild. Leave the search root unpublished until that current
            // rebuild completes; its refresh path publishes after `.ready`.
            return
        }
        // After the rebuild, not before: a folder search re-run by
        // `setRoot(_:)` reads `workspaceFileIndex` through the closure
        // captured at `FolderSearchModel.init` time, so it must see the
        // freshly-rebuilt snapshot for the new root, not the old (or
        // `.empty`) one.
        folderSearchModel.setRoot(indexRoot, lexicalRoot: fileTreeModel.root)
        pendingFolderSearchRoot = nil
        pendingFolderSearchRootGeneration = nil
    }

    func stopWorkspaceEvents() {
        workspaceEventDebounceTask?.cancel()
        workspaceEventDebounceTask = nil
        workspaceEventTask?.cancel()
        workspaceEventTask = nil
        workspaceEventSource?.cancel()
        workspaceEventSource = nil
        workspaceEventRoot = nil
        workspaceEventPaths = []
    }

    @discardableResult
    private func startWorkspaceEvents(paths: [String], root: URL, request: UInt) -> Bool {
        guard let source = try? makeWorkspaceEventSource(paths) else {
            // The key-window refresh remains a fallback when the OS cannot
            // establish the recursive stream for a selected folder.
            return false
        }
        workspaceEventSource = source
        workspaceEventRoot = root
        workspaceEventPaths = paths
        workspaceEventTask = Task { @MainActor [weak self] in
            for await event in source.events {
                guard !Task.isCancelled, let self else { return }
                observedWorkspaceEvent(event, root: root, request: request)
            }
        }
        return true
    }

    private func observedWorkspaceEvent(_ event: WorkspaceFileChange, root: URL, request: UInt) {
        guard !isClosed, workspaceRootRequestGeneration == request,
              fileTreeModel.rootAccessURL == root else { return }
        if event == .rootChanged || !fileTreeModel.selectedRootIsCurrent {
            retireWorkspaceResults()
        }
        workspaceEventDebounceTask?.cancel()
        workspaceEventDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !isClosed,
                  workspaceRootRequestGeneration == request,
                  fileTreeModel.rootAccessURL == root else { return }
            workspaceEventDebounceTask = nil
            await refreshWorkspaceIndex()
        }
    }

    private func scheduleWorkspaceMonitoringRetry(root: URL, request: UInt) {
        workspaceEventDebounceTask?.cancel()
        workspaceEventDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !isClosed,
                  workspaceRootRequestGeneration == request,
                  fileTreeModel.rootAccessURL == root else { return }
            workspaceEventDebounceTask = nil
            await refreshWorkspaceIndex()
        }
    }

    private func retireWorkspaceResults() {
        lastWorkspaceIndexRefresh = nil
        lastWorkspaceIndexRefreshRoot = nil
        lastWorkspaceIndexRefreshGeneration = nil
        coordinator?.closeQuickOpenIfOrigin(self)
        folderSearchModel.rootAccessWasRevoked()
    }
}
