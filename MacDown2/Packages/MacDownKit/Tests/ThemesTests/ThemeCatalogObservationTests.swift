import Darwin
import Foundation
import Testing
@testable import Themes

private actor ThemeObservationSignal {
    private var signalled = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func signal() {
        signalled = true
        let current = waiters.values
        waiters.removeAll()
        for waiter in current {
            waiter.resume(returning: true)
        }
    }

    func wait() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if signalled {
                    continuation.resume(returning: true)
                } else if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: false)
    }

    func withinDeadline() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.wait() }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return false
                }
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

struct ThemeCatalogObservationTests {
    @Test func observesCreationThenAnInPlaceEditWithoutDirectoryEntryChanges() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let created = ThemeObservationSignal(); let modified = ThemeObservationSignal()
        var theme = BundledThemes.light
        theme.name = "Initial"
        let first = try ThemeFile(theme: theme)
        theme.name = "Updated"
        let second = try ThemeFile(theme: theme, stableID: first.stableID)
        try await observing(store, onChange: { _ in
            do {
                let state = try await store.reload()
                let name = state.catalog.customTheme(id: first.stableID)?.displayName
                if name == "Initial" {
                    await created.signal()
                }
                if name == "Updated" {
                    await modified.signal()
                }
            } catch { Issue.record(error) }
        }, perform: {
            try fixture.put(first)
            #expect(await created.withinDeadline())
            var before = stat(); var after = stat()
            #expect(stat(fixture.root.path, &before) == 0)
            let data = try second.encoded()
            let handle = try FileHandle(forWritingTo: fixture.url(first.stableID))
            try handle.write(contentsOf: data)
            try handle.truncate(atOffset: UInt64(data.count))
            try handle.synchronize()
            try handle.close()
            #expect(stat(fixture.root.path, &after) == 0)
            #expect(before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec)
            #expect(before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec)
            #expect(await modified.withinDeadline())
        })
    }

    @Test func oneObserverRemainsOccupiedUntilStopDrainsAndCanThenRestart() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        for _ in 0 ..< 25 {
            let stream = try await store.observeChanges()
            await #expect(throws: ThemeStorageError.alreadyObserving) { try await store.observeChanges() }
            await store.stopObserving()
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next() // At most one buffered advisory event.
            #expect(await iterator.next() == nil)
        }
    }

    @Test func cancellingTheConsumerTerminatesItsStreamAndExplicitStopDrainsIt() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let stream = try await store.observeChanges()
        let started = ThemeObservationSignal()
        let consumer = Task {
            await started.signal()
            for await _ in stream {}
        }
        #expect(await started.withinDeadline())
        consumer.cancel()
        await consumer.value
        await store.stopObserving()
        _ = try await store.observeChanges()
        await store.stopObserving()
    }

    @Test func rootMovementIsReportedAndDoesNotCreateANewReadAuthority() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let store = try ThemeCatalogStore(directoryURL: fixture.root)
        let rootChanged = ThemeObservationSignal()
        try await observing(store, onChange: { event in
            if event == .rootChanged {
                await rootChanged.signal()
            }
        }, perform: {
            try FileManager.default.moveItem(at: fixture.root, to: fixture.base.appendingPathComponent("moved"))
            try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            #expect(await rootChanged.withinDeadline())
            await #expect(throws: ThemeStorageError.directoryChanged) { try await store.reload() }
        })
    }

    private func observing(
        _ store: ThemeCatalogStore,
        onChange: @escaping @Sendable (ThemeCatalogChange) async -> Void,
        perform: @Sendable () async throws -> Void
    ) async throws {
        let stream = try await store.observeChanges()
        let consumer = Task { for await event in stream {
            await onChange(event)
        } }
        do {
            try await perform()
        } catch {
            await store.stopObserving()
            consumer.cancel()
            await consumer.value
            throw error
        }
        await store.stopObserving()
        consumer.cancel()
        await consumer.value
    }
}
