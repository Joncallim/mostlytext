import AppKit
import LocalResourceAccess
import Observation
import Themes

@MainActor
@Observable
final class ThemeCatalogModel {
    enum Location: Sendable {
        case applicationSupport
        case isolatedSession(URL)
        case existingDirectory(URL)
    }

    enum Status { case idle, loading, ready, unavailable, stopped }

    var status = Status.idle
    var state: ThemeCatalogState?
    var isBusy = false
    var problem: String?
    var pendingImport: PreparedThemeImport?
    var pendingDeletion: PreparedThemeDeletion?
    var operationID = UUID()
    var affectedThemeID: String?
    let controller: ThemeController
    let location: Location
    @ObservationIgnored var store: ThemeCatalogStore?
    @ObservationIgnored var generation = UUID()
    @ObservationIgnored var startupTask: Task<Void, Never>?
    @ObservationIgnored var observationTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var debounceTask: Task<Void, Never>?
    @ObservationIgnored var recheckTask: Task<Void, Never>?
    @ObservationIgnored var refreshRequested = false
    @ObservationIgnored var readCancellation: ResourceCancellation?
    @ObservationIgnored var confirmationTask: Task<Void, Never>?
    @ObservationIgnored var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(controller: ThemeController, location: Location) {
        self.controller = controller
        self.location = location
    }

    var canManage: Bool {
        status == .ready && !isBusy && pendingImport == nil && pendingDeletion == nil
    }

    var customThemes: [ThemeFile] {
        state?.catalog.customThemes ?? []
    }

    func start() {
        guard status == .idle else { return }
        status = .loading
        let token = generation
        let location = location
        startupTask = Task { [weak self] in
            let opening = Task.detached(priority: .utility) { try Self.openStore(location: location) }
            do {
                let store = try await withTaskCancellationHandler {
                    try await opening.value
                } onCancel: { opening.cancel() }
                guard let self, generation == token, !Task.isCancelled else { return }
                self.store = store
                let events = try await store.observeChanges()
                guard generation == token, !Task.isCancelled else {
                    await store.stopObserving(); return
                }
                observationTask = Task { [weak self] in
                    for await event in events {
                        guard let self, generation == token, !Task.isCancelled else { break }
                        scheduleRefresh(immediate: event == .rootChanged)
                    }
                }
                requestRefresh()
                startupTask = nil
            } catch {
                guard let self, generation == token else { return }
                if let store {
                    await store.stopObserving()
                }
                status = .unavailable
                problem = Self.message(for: error)
                startupTask = nil
            }
        }
    }

    func scheduleRefresh(immediate: Bool = false) {
        debounceTask?.cancel()
        let token = generation
        debounceTask = Task { [weak self] in
            do {
                if !immediate {
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch { return }
            guard let self, generation == token, !Task.isCancelled else { return }
            requestRefresh()
        }
    }

    func requestRefresh() {
        guard let store, status != .unavailable else { return }
        refreshRequested = true
        guard refreshTask == nil else { return }
        let token = generation
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, generation == token, refreshRequested else { break }
                refreshRequested = false
                let result: Result<ThemeCatalogState, Error>
                do {
                    result = try await .success(store.reload())
                } catch {
                    result = .failure(error)
                }
                guard generation == token, !Task.isCancelled else { break }
                switch result {
                case let .success(value): publish(value)
                case let .failure(error):
                    problem = Self.message(for: error)
                    status = .unavailable
                    await store.stopObserving()
                    refreshRequested = false
                }
            }
            guard let self, generation == token else { return }
            refreshTask = nil
        }
    }

    func publish(_ value: ThemeCatalogState) {
        guard state == nil || value.catalog.revision >= (state?.catalog.revision ?? 0) else { return }
        state = value
        status = .ready
        controller.applyCustomCatalog(value.catalog)
        recheckTask?.cancel()
        recheckTask = nil
        if value.needsRecheck {
            let token = generation
            recheckTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(750))
                } catch {
                    return
                }
                guard let self, generation == token, !Task.isCancelled else { return }
                requestRefresh()
            }
        }
    }

    func cancelPendingImport() {
        pendingImport = nil
    }

    func cancelPendingDeletion() {
        pendingDeletion = nil
    }

    func clearProblem() {
        problem = nil
    }

    func revealDirectory() async {
        guard let url = try? await store?.currentDirectoryURL() else {
            problem = Self.message(for: ThemeStorageError.directoryChanged)
            return
        }
        NSWorkspace.shared.open(url)
    }

    func cancel() {
        generation = UUID()
        startupTask?.cancel()
        observationTask?.cancel()
        refreshTask?.cancel()
        debounceTask?.cancel()
        recheckTask?.cancel()
        pendingImport = nil
        pendingDeletion = nil
        confirmationTask?.cancel()
        readCancellation?.cancel()
    }

    func finishMutation() {
        isBusy = false
        readCancellation = nil
        let waiting = mutationWaiters
        mutationWaiters.removeAll()
        for waiter in waiting {
            waiter.resume()
        }
    }

    private func waitForMutation() async {
        guard isBusy else { return }
        await withCheckedContinuation { mutationWaiters.append($0) }
    }

    func shutdown() async {
        cancel()
        await startupTask?.value
        await observationTask?.value
        await refreshTask?.value
        await confirmationTask?.value
        await waitForMutation()
        await store?.stopObserving()
        startupTask = nil; observationTask = nil; refreshTask = nil
        debounceTask = nil; recheckTask = nil
        store = nil
        status = .stopped
    }
}
