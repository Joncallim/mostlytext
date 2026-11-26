import Foundation

@MainActor
extension FileTreeModel {
    func rebuildRows() {
        guard let root, case let .loaded(rootEntries)? = children[root] else { return }
        let arranged = FileTreeArrangement.arrange(
            rootEntries,
            filter: preferences.filter,
            supportedExtensions: supportedExtensions
        )
        // The root is the common 10k-entry case. Reuse the previous row
        // capacity where possible and avoid the otherwise repeated growth
        // allocations while flattening.
        var output: [FileTreeRow] = []
        output.reserveCapacity(max(rows.count, rootEntries.count))
        entriesByURL.removeAll(keepingCapacity: true)
        append(arranged, depth: 0, into: &output)
        rows = output
        availability = if rootEntries.isEmpty {
            .empty
        } else {
            arranged.isEmpty ? .emptyAfterFilter : .ready
        }
    }

    private func append(_ entries: [DirectoryEntry], depth: Int, into output: inout [FileTreeRow]) {
        for entry in entries {
            entriesByURL[entry.url] = entry
            let isExpanded = expanded.contains(entry.url)
            let isLoading = if case .loading? = children[entry.url] {
                true
            } else {
                false
            }
            let loadError: String? = if case let .failed(message)? = children[entry.url] {
                message
            } else {
                nil
            }
            output.append(
                FileTreeRow(
                    entry: entry,
                    depth: depth,
                    isExpanded: isExpanded,
                    isLoading: isLoading,
                    loadError: loadError
                )
            )
            guard entry.isDirectory, isExpanded, !entry.isPackage,
                  case let .loaded(grandchildren)? = children[entry.url] else { continue }
            append(
                FileTreeArrangement
                    .arrange(grandchildren, filter: preferences.filter, supportedExtensions: supportedExtensions),
                depth: depth + 1,
                into: &output
            )
        }
    }

    func findEntry(_ url: URL) -> DirectoryEntry? {
        entriesByURL[url]
    }

    func startWatching(_ url: URL, expectedGeneration: UInt) {
        guard watchers[url] == nil else { return }
        do {
            watchers[url] = try watcher.watch(url) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, generation == expectedGeneration else { return }
                    watchEvent(event, at: url, expectedGeneration: expectedGeneration)
                }
            }
        } catch {
            // Live updates are best effort: a folder that cannot be opened for
            // watching (typically an unreadable one) must not raise a modal
            // "Folder Operation Failed" — its listing failure is already shown
            // inline, and the watcher error text ("doesn't exist") is wrong.
        }
    }

    private func watchEvent(_ event: DirectoryWatchEvent, at url: URL, expectedGeneration: UInt) {
        guard generation == expectedGeneration, url == root || expanded.contains(url) else { return }
        if event == .vanished {
            if url == root {
                notifyRootAccessWillChange()
                rootIsTerminal = true
                availability = .rootVanished
                rows = []
                tearDown()
            } else {
                evictSubtree(url)
                rebuildRows()
            }
            return
        }
        rescanTasks[url]?.cancel()
        rescanTasks[url] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, generation == expectedGeneration,
                  url == root || expanded.contains(url) else { return }
            await reload(url, isRoot: url == root, expectedGeneration: expectedGeneration)
        }
    }

    func cancelWatcher(at url: URL) {
        watchers.removeValue(forKey: url)?.cancel()
    }

    func evictSubtree(_ url: URL) {
        let prefix = url.standardizedFileURL.pathComponents
        let reloadKeys = reloadTokens.keys.filter { $0.pathComponents.starts(with: prefix) }
        for key in reloadKeys {
            // A missing token invalidates every in-flight reader while avoiding
            // an unbounded token map for deleted/churned subtrees.
            reloadTokens.removeValue(forKey: key)
        }
        for key in watchers.keys.filter({ $0.pathComponents.starts(with: prefix) }) {
            cancelWatcher(at: key)
        }
        let taskKeys = rescanTasks.keys.filter { $0.pathComponents.starts(with: prefix) }
        for key in taskKeys {
            rescanTasks.removeValue(forKey: key)?.cancel()
        }
        let childKeys = children.keys.filter { $0.pathComponents.starts(with: prefix) }
        for key in childKeys {
            children.removeValue(forKey: key)
        }
        expanded = Set(expanded.filter { !$0.pathComponents.starts(with: prefix) })
    }

    func reconcileRowState() {
        let visible = Set(rows.map(\.id))
        if let selectedURL, !visible.contains(selectedURL) {
            self.selectedURL = nil
        }
        if let renamingURL, !visible.contains(renamingURL) {
            self.renamingURL = nil
        }
        if let pendingOpenURL, !visible.contains(pendingOpenURL) {
            self.pendingOpenURL = nil
        }
    }

    func rekey(_ state: DirectoryLoadState, from old: URL, to new: URL) -> DirectoryLoadState {
        guard case let .loaded(entries) = state else { return state }
        return .loaded(entries.map { entry in
            let components = entry.url.pathComponents
            guard components.starts(with: old.pathComponents) else { return entry }
            let suffix = components.dropFirst(old.pathComponents.count).joined(separator: "/")
            let url = new.appendingPathComponent(suffix, isDirectory: entry.isDirectory)
            return DirectoryEntry(
                url: url,
                isDirectory: entry.isDirectory,
                isHidden: entry.isHidden,
                isPackage: entry.isPackage,
                isSymbolicLink: entry.isSymbolicLink
            )
        })
    }

    func oldEntry(for url: URL, in entries: [DirectoryEntry]) -> DirectoryEntry? {
        entries.first { $0.url.path == url.path }
    }

    public func containsCurrentNode(_ url: URL) -> Bool {
        findEntry(url.standardizedFileURL) != nil
    }

    func isLoaded(_ state: DirectoryLoadState) -> Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    func loadedEntries(at url: URL) -> [DirectoryEntry] {
        guard case let .loaded(entries)? = children[url] else { return [] }
        return entries
    }

    func wasExpandable(_ entry: DirectoryEntry, in prior: [DirectoryEntry]) -> Bool {
        oldEntry(for: entry.url, in: prior)?.isDirectory == true && (!entry.isDirectory || entry.isPackage)
    }
}
