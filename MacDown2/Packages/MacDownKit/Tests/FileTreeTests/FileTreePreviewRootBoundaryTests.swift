@testable import FileTree
import Foundation
import Testing

@MainActor
@Suite("Preview root access publication")
struct FileTreePreviewRootBoundaryTests {
    @Test func samePathScopeReplacementNotifiesWhileOldScopeIsStillOwned() async {
        let root = URL(fileURLWithPath: "/tmp/preview-root", isDirectory: true)
        let firstScope = URL(fileURLWithPath: "/tmp/preview-root-first", isDirectory: true)
        let secondScope = URL(fileURLWithPath: "/tmp/preview-root-second", isDirectory: true)
        let model = makeModel(root: root)
        await model.setRoot(root, accessURL: firstScope)
        var observedOldAccess: [URL?] = []
        model.setRootAccessWillChange {
            observedOldAccess.append(model.rootAccessURL)
        }

        await model.setRoot(root, accessURL: secondScope)

        #expect(observedOldAccess.first == firstScope.standardizedFileURL)
        #expect(model.root == root.standardizedFileURL)
        #expect(model.rootAccessURL == secondScope.standardizedFileURL)
    }

    @Test func acceptedRootRenameNotifiesBeforeNewRootOrScopePublication() async {
        let root = URL(fileURLWithPath: "/tmp/preview-old-root", isDirectory: true)
        let renamed = URL(fileURLWithPath: "/tmp/preview-new-root", isDirectory: true)
        let model = makeModel(root: root)
        await model.setRoot(root)
        var oldRootAtNotification: URL?
        var oldAccessAtNotification: URL?
        model.setRootAccessWillChange {
            if oldRootAtNotification == nil {
                oldRootAtNotification = model.root
                oldAccessAtNotification = model.rootAccessURL
            }
        }

        model.itemWasRenamed(from: root, to: renamed)

        #expect(oldRootAtNotification == root.standardizedFileURL)
        #expect(oldAccessAtNotification == root.standardizedFileURL)
        #expect(model.root == renamed.standardizedFileURL)
    }

    @Test func vanishedRootNotifiesBeforeTerminalAvailability() async {
        let root = URL(fileURLWithPath: "/tmp/preview-vanished-root", isDirectory: true)
        let watcher = EmittingPreviewWatcher()
        let model = FileTreeModel(
            reader: StaticReader(contents: [root: []]), watcher: watcher,
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
        await model.setRoot(root)
        let (events, signal) = AsyncStream<Bool>.makeStream()
        var didSignal = false
        model.setRootAccessWillChange {
            guard !didSignal else { return }
            didSignal = true
            let wasNonterminal = if case .rootVanished = model.availability {
                false
            } else {
                true
            }
            signal.yield(model.rootAccessURL == root.standardizedFileURL && wasNonterminal)
            signal.finish()
        }

        watcher.emit(.vanished)
        let observedBeforeTerminal = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await observed in events {
                    return observed
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        #expect(observedBeforeTerminal)
        #expect(model.rootAccessURL == nil)
        #expect(model.availability == .rootVanished)
        #expect(model.availability.message(locale: Locale(identifier: "en")) == "The folder is no longer available.")
        #expect(FolderAvailability.rootUnreadable(reason: "Disk error").message(
            locale: Locale(identifier: "fr")
        ) == "Disk error")
    }

    private func makeModel(root: URL) -> FileTreeModel {
        FileTreeModel(
            reader: StaticReader(contents: [root: []]),
            watcher: RecordingWatching(),
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
    }
}

private final class EmittingPreviewWatcher: @unchecked Sendable, DirectoryWatching {
    private let lock = NSLock()
    private var callback: (@Sendable (DirectoryWatchEvent) -> Void)?

    func watch(
        _: URL, onChange: @escaping @Sendable (DirectoryWatchEvent) -> Void
    ) throws -> any DirectoryWatcherHandle {
        lock.lock()
        callback = onChange
        lock.unlock()
        return TestWatcher()
    }

    func emit(_ event: DirectoryWatchEvent) {
        lock.lock()
        let callback = callback
        lock.unlock()
        callback?(event)
    }
}
