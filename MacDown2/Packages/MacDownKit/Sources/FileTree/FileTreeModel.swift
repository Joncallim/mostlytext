import Foundation
import Observation

enum DirectoryLoadState: Sendable {
    case notLoaded
    case loading
    case loaded([DirectoryEntry])
    case failed(String)
}

@MainActor @Observable
public final class FileTreeModel {
    public internal(set) var root: URL? {
        willSet {
            if root != newValue {
                rootAccessWillChange?()
            }
        }
    }

    public internal(set) var availability: FolderAvailability = .noRoot
    public internal(set) var rows: [FileTreeRow] = []
    public var selectedURL: URL?
    public var renamingURL: URL?
    public var pendingOpenURL: URL?
    public internal(set) var lastOperationError: FileTreeOperationError?
    public var watchedDirectoryCount: Int {
        watchers.count
    }

    public var rootAccessURL: URL? {
        rootAccessScope?.url
    }

    let reader: any DirectoryReading
    let mutator: any FileSystemMutating
    let watcher: any DirectoryWatching
    public let preferences: FileTreePreferences
    let supportedExtensions: Set<String>
    var expanded: Set<URL> = []
    var children: [URL: DirectoryLoadState] = [:]
    var watchers: [URL: any DirectoryWatcherHandle] = [:]
    var rescanTasks: [URL: Task<Void, Never>] = [:]
    var rootAccessScope: FolderAccessScope? {
        willSet {
            if rootAccessScope !== newValue {
                rootAccessWillChange?()
            }
        }
    }

    @ObservationIgnored private var rootAccessWillChange: (@MainActor () -> Void)?
    var generation: UInt = 0
    var reloadTokens: [URL: UInt] = [:]
    var nextReloadToken: UInt = 0
    var rootIsTerminal = false
    var entriesByURL: [URL: DirectoryEntry] = [:]
    private var preferenceObserverID: UUID?

    public init(
        reader: any DirectoryReading = FileSystemDirectoryReader(),
        mutator: any FileSystemMutating = FileSystemMutator(),
        watcher: any DirectoryWatching = FileSystemDirectoryWatching(),
        preferences: FileTreePreferences,
        supportedExtensions: Set<String>
    ) {
        self.reader = reader; self.mutator = mutator; self.watcher = watcher
        self.preferences = preferences
        self.supportedExtensions = Set(supportedExtensions.map { $0.lowercased() })
    }

    /// Runs before a root URL or its scope is replaced or torn down, including a same-path scope replacement.
    /// The callback must revoke old preview authority synchronously and must not mutate this model.
    public func setRootAccessWillChange(_ callback: (@MainActor () -> Void)?) {
        precondition(callback == nil || rootAccessWillChange == nil, "Root access observer already installed")
        rootAccessWillChange = callback
    }

    func notifyRootAccessWillChange() {
        rootAccessWillChange?()
    }

    public func setRoot(_ url: URL?, accessURL: URL? = nil) async {
        tearDown()
        root = url?.standardizedFileURL
        rootIsTerminal = false
        selectedURL = nil; renamingURL = nil; pendingOpenURL = nil; lastOperationError = nil
        children = [:]; expanded = []; entriesByURL = [:]
        guard let root else { availability = .noRoot; rows = []; return }
        rootAccessScope = FolderAccessScope(url: accessURL?.standardizedFileURL ?? root)
        let expectedGeneration = generation
        children[root] = .loading; availability = .loading; rows = []
        await reload(root, isRoot: true, expectedGeneration: expectedGeneration)
        if generation == expectedGeneration, self.root == root, case .loaded = children[root] {
            startWatching(root, expectedGeneration: expectedGeneration)
        }
    }

    public func expand(_ url: URL) async {
        let key = url.standardizedFileURL
        let expectedGeneration = generation
        guard let entry = findEntry(key), entry.isDirectory, !entry.isPackage else { return }
        expanded.insert(key)
        if case .failed? = children[key] {
            children[key] = .loading
        }
        if case .notLoaded? = children[key] {
            children[key] = .loading
        }
        if children[key] == nil {
            children[key] = .loading
        }
        rebuildRows()
        if case .loading = children[key] {
            await reload(key, expectedGeneration: expectedGeneration)
        }
        guard generation == expectedGeneration, expanded.contains(key) else { return }
        startWatching(key, expectedGeneration: expectedGeneration)
        rebuildRows()
    }

    public func collapse(_ url: URL) {
        let key = url.standardizedFileURL
        expanded.remove(key)
        rescanTasks.removeValue(forKey: key)?.cancel()
        cancelWatcher(at: key)
        rebuildRows()
    }

    public func toggleExpansion(_ url: URL) async {
        if expanded.contains(url.standardizedFileURL) {
            collapse(url)
        } else {
            await expand(url)
        }
    }

    public func rescanExpandedDirectories() async {
        guard let root, !rootIsTerminal else { return }
        let expectedGeneration = generation
        await reload(root, isRoot: true, expectedGeneration: expectedGeneration)
        if generation == expectedGeneration, case .loaded = children[root] {
            startWatching(root, expectedGeneration: expectedGeneration)
        }
        for url in expanded {
            guard generation == expectedGeneration else { return }
            guard expanded.contains(url) else { continue }
            await reload(url, expectedGeneration: expectedGeneration)
            if generation == expectedGeneration, expanded.contains(url), case .loaded = children[url] {
                startWatching(url, expectedGeneration: expectedGeneration)
            }
        }
    }

    public func tearDown() {
        generation &+= 1
        for task in rescanTasks.values {
            task.cancel()
        }
        rescanTasks = [:]
        for handle in watchers.values {
            handle.cancel()
        }
        watchers = [:]
        rootAccessScope = nil
        reloadTokens = [:]
    }

    public func rebuildForPreferencesChange() {
        rebuildRows()
        reconcileRowState()
    }

    public func recordOperationError(_ error: Error) {
        lastOperationError = error as? FileTreeOperationError ?? .underlying(error.localizedDescription)
    }

    /// Called after every successful file-tree mutation so dependents that cache
    /// the folder's contents (the workspace file index) can refresh.
    public var onDidMutate: (@MainActor () -> Void)?

    public func clearOperationError() {
        lastOperationError = nil
    }

    /// Capture before creating a task. Passing this to CRUD prevents a queued
    /// old-root task from mutating a replacement root, including A → B → A.
    public func beginOperation() -> FileTreeOperationContext {
        FileTreeOperationContext(root: root, generation: generation)
    }

    public func isCurrent(_ context: FileTreeOperationContext) -> Bool {
        operationIsCurrent(context)
    }

    public func startObservingPreferences() {
        guard preferenceObserverID == nil else { return }
        preferenceObserverID = preferences.addObserver { [weak self] in
            self?.rebuildForPreferencesChange()
        }
    }

    public func dispose() {
        tearDown()
        if let preferenceObserverID {
            preferences.removeObserver(preferenceObserverID)
            self.preferenceObserverID = nil
        }
    }

    @discardableResult
    public func reveal(_ url: URL) async -> Bool {
        let target = url.standardizedFileURL
        let context = beginOperation()
        guard let root, target.pathComponents.starts(with: root.pathComponents), target != root else { return false }
        var ancestor = target.deletingLastPathComponent()
        var ancestors: [URL] = []
        while ancestor != root {
            ancestors.append(ancestor); ancestor = ancestor.deletingLastPathComponent()
        }
        for directory in ancestors.reversed() {
            await expand(directory)
            // A replacement root can publish the same path while an older
            // directory read is suspended. That old reveal must not select
            // a node in the new root generation.
            guard isCurrent(context) else { return false }
        }
        guard isCurrent(context), findEntry(target) != nil else { return false }
        selectedURL = target
        return true
    }

    func reload(_ url: URL, isRoot: Bool = false, expectedGeneration: UInt) async {
        let key = url.standardizedFileURL
        precondition(nextReloadToken < .max, "Reload token space exhausted")
        nextReloadToken += 1
        let reloadToken = nextReloadToken
        reloadTokens[key] = reloadToken
        do {
            let listed = try await contents(url)
            guard generation == expectedGeneration, reloadTokens[key] == reloadToken else { return }
            applyReload(listed, at: url, isRoot: isRoot)
        } catch {
            guard generation == expectedGeneration, reloadTokens[key] == reloadToken else { return }
            children[url] = .failed(error.localizedDescription)
            if isRoot {
                availability = .rootUnreadable(reason: error.localizedDescription)
                rows = []
            } else {
                rebuildRows()
            }
        }
    }

    private func applyReload(_ listed: [DirectoryEntry], at url: URL, isRoot _: Bool) {
        let wasLoaded = children[url].map(isLoaded) ?? false
        let prior = loadedEntries(at: url)
        let diff = FileTreeDiff.diff(old: prior, new: listed)
        for removed in diff.removed where removed.isDirectory {
            evictSubtree(removed.url)
        }
        for changed in diff.changed where wasExpandable(changed, in: prior) {
            evictSubtree(changed.url)
        }
        children[url] = .loaded(listed)
        if !diff.isEmpty || !wasLoaded {
            rebuildRows()
            reconcileRowState()
        }
    }
}
