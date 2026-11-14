import AppKit
import AppSettings
import Darwin
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Measures the actual app-test process and its open file-watch descriptors.
/// Wakeup counts are observations, not a stable CI performance threshold: other
/// work in the process can also wake it. The positive rename controls that the
/// watcher was active during the idle interval.
@Suite("External file window occupancy", .serialized)
@MainActor
struct ExternalFileWindowOccupancyTests {
    @Test func aHiddenWindowUpdatesItsTitleFromChangesAndStopsAfterClose() async throws {
        let fixture = try Fixture()
        let model = fixture.coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "initial"))
        let controller = fixture.makeWindow(model: model)
        fixture.coordinator.controllers = [controller]
        let window = try #require(controller.window)
        let untitled = String(localized: "Untitled")
        #expect(!window.isKeyWindow)
        #expect(window.title == untitled)

        try await Task.sleep(for: .milliseconds(150))
        model.tabStore.updateActiveDocument { $0.updatingText("local draft") }
        try await waitUntil(.milliseconds(750), "dirty title without an idle polling tick") {
            window.title == "● \(untitled)" && window.isDocumentEdited
        }
        model.tabStore.updateActiveDocument { _ in FileDocument(text: "clean replacement") }
        try await waitUntil(.milliseconds(750), "clean title after document replacement") {
            window.title == untitled && !window.isDocumentEdited
        }

        fixture.coordinator.removeController(controller)
        controller.close()
        #expect(controller.isClosed)
        let retiredTitle = window.title
        model.tabStore.updateActiveDocument { $0.updatingText("another change") }
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.title == retiredTitle, "retired observation must not update a closed window")
    }

    @Test func threeRealWindowsHaveBoundedWatchDescriptorsAndAnExternalChangePositive() async throws {
        let fixture = try Fixture()
        let windows = try makeFileWindows(fixture: fixture)
        let controllers = windows.controllers
        let sourceURLs = windows.sources
        let directoryURLs = windows.directories
        fixture.coordinator.controllers = controllers
        defer {
            for controller in controllers where !controller.isClosed {
                fixture.coordinator.removeController(controller)
                controller.close()
            }
        }
        for controller in controllers {
            await controller.externalFileController.bindTask?.value
        }
        let targets = sourceURLs + directoryURLs
        try await waitUntil(.seconds(5), "three file and parent watches") {
            (try? watcherDescriptors(for: targets).values.allSatisfy { $0 == 1 }) == true
        }
        let bound = try watcherDescriptors(for: targets)
        #expect(bound.values.allSatisfy { $0 == 1 }, "one live file and parent watcher per document")
        let first = controllers[0]
        let firstIdentity = try #require(first.model.tabStore.activeTab?.id.uuidString)
        let firstEditor = try #require(first.editorStore.existingSystem(for: firstIdentity))
        firstEditor.selectedRange = NSRange(location: 3, length: 4)
        firstEditor.scrollOffset = 25

        let idleStart = try processWakeups()
        try await Task.sleep(for: .seconds(4))
        let idleEnd = try processWakeups()
        #expect(try watcherDescriptors(for: targets) == bound, "idle watches must not accumulate")

        let positive = try await verifyExternalReplacementAndSession(
            fixture: fixture, controller: first,
            source: sourceURLs[0], directory: directoryURLs[0]
        )
        let closed = try await measureClosedWindows(fixture: fixture, controllers: controllers, targets: targets)

        let record: [String: Any] = [
            "window_count": 3,
            "file_watch_descriptors": sourceURLs.count,
            "parent_watch_descriptors": directoryURLs.count,
            "idle_interrupt_wakeups": idleEnd.interrupt - idleStart.interrupt,
            "idle_platform_idle_wakeups": idleEnd.platformIdle - idleStart.platformIdle,
            "positive_interrupt_wakeups": positive.interrupt,
            "positive_platform_idle_wakeups": positive.platformIdle,
            "closed_interrupt_wakeups": closed.interrupt,
            "closed_platform_idle_wakeups": closed.platformIdle,
        ]
        try preserveMeasurement(record)
    }

    private func preserveMeasurement(_ record: [String: Any]) throws {
        print("external-window-process-occupancy \(record)")
        if let directory = ProcessInfo.processInfo.environment["MOSTLYTEXT_EXTERNAL_PROCESS_OUTPUT"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url.appendingPathComponent("window-occupancy.json"), options: .atomic)
        }
    }

    private struct WindowSet {
        let controllers: [WindowController]
        let sources: [URL]
        let directories: [URL]
    }

    private func makeFileWindows(fixture: Fixture) throws -> WindowSet {
        var controllers: [WindowController] = []
        var sources: [URL] = []
        var directories: [URL] = []
        for index in 0 ..< 3 {
            let directory = fixture.root.appendingPathComponent("document-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("source.md")
            try "original-\(index)".write(to: source, atomically: true, encoding: .utf8)
            let model = fixture.coordinator.makeWindowModel()
            try model.tabStore.newTab(document: FileDocument(
                fileURL: source, recoveryBuffer: fixture.recovery
            ).load())
            controllers.append(fixture.makeWindow(model: model))
            sources.append(source)
            directories.append(directory)
        }
        return WindowSet(controllers: controllers, sources: sources, directories: directories)
    }

    private func measureClosedWindows(
        fixture: Fixture, controllers: [WindowController], targets: [URL]
    ) async throws -> (interrupt: UInt64, platformIdle: UInt64) {
        for controller in controllers {
            fixture.coordinator.removeController(controller)
            controller.close()
        }
        try await waitUntil(.seconds(5), "watch descriptors after closing all windows") {
            (try? watcherDescriptors(for: targets).values.allSatisfy { $0 == 0 }) == true
        }
        try await Task.sleep(for: .seconds(1))
        let start = try processWakeups()
        try await Task.sleep(for: .seconds(4))
        let end = try processWakeups()
        #expect(try watcherDescriptors(for: targets).values.allSatisfy { $0 == 0 })
        return (end.interrupt - start.interrupt, end.platformIdle - start.platformIdle)
    }

    private func verifyExternalReplacementAndSession(
        fixture: Fixture, controller: WindowController, source: URL, directory: URL
    ) async throws -> (interrupt: UInt64, platformIdle: UInt64) {
        let identity = try #require(controller.model.tabStore.activeTab?.id.uuidString)
        let editor = try #require(controller.editorStore.existingSystem(for: identity))
        let replacement = directory.appendingPathComponent("replacement.md")
        try "external replacement".write(to: replacement, atomically: true, encoding: .utf8)
        let originalIdentity = try watcherIdentity(for: source)
        let positiveStart = try processWakeups()
        guard rename(replacement.path, source.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try await waitUntil(.seconds(5), "real watcher to editor reconciliation") {
            controller.model.activeDocument?.text == "external replacement"
                && controller.model.activeDocument?.state == .clean
                && editor.textView.string == "external replacement"
        }
        let positiveEnd = try processWakeups()
        #expect(try String(contentsOf: source, encoding: .utf8) == "external replacement")
        #expect(editor.selectedRange == NSRange(location: 3, length: 4))
        #expect(editor.scrollOffset == 25)
        try await requireWatcherTransition(
            retired: originalIdentity, source: source, directory: directory, stage: "first replacement"
        )

        let shortReplacement = directory.appendingPathComponent("short.md")
        try "short".write(to: shortReplacement, atomically: true, encoding: .utf8)
        let intermediateIdentity = try watcherIdentity(for: source)
        guard rename(shortReplacement.path, source.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try await waitUntil(.seconds(5), "shorter external replacement and selection clamp") {
            controller.model.activeDocument?.text == "short" && editor.textView.string == "short"
        }
        #expect(editor.selectedRange == NSRange(location: 3, length: 2))
        #expect(editor.scrollOffset == 25)
        #expect(try String(contentsOf: source, encoding: .utf8) == "short")
        try await requireWatcherTransition(
            retired: intermediateIdentity, source: source, directory: directory, stage: "second replacement"
        )
        let sessionResult = await fixture.coordinator.saveSessionResult()
        #expect(sessionResult.persisted)
        let session = try #require(WorkspaceSessionStore(
            fileURL: fixture.root.appendingPathComponent("session.json")
        ).loadSession())
        let recordedFirst = try #require(session.tabs.first { $0.id.uuidString == identity })
        #expect(recordedFirst.cursorPosition == 3)
        #expect(recordedFirst.selectionLength == 2)
        #expect(recordedFirst.scrollOffset == 25)
        return (
            positiveEnd.interrupt - positiveStart.interrupt,
            positiveEnd.platformIdle - positiveStart.platformIdle
        )
    }

    private func waitUntil(
        _ timeout: Duration, _ stage: String, condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(stage)")
        throw CancellationError()
    }

    private struct WatcherIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private func watcherIdentity(for url: URL) throws -> WatcherIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return WatcherIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func watcherDescriptors(for urls: [URL]) throws -> [String: Int] {
        var identities: [String: WatcherIdentity] = [:]
        for url in urls {
            identities[url.path] = try watcherIdentity(for: url)
        }
        let live = try eventOnlyDescriptorIdentities()
        var counts = Dictionary(uniqueKeysWithValues: urls.map { ($0.path, 0) })
        for (path, identity) in identities {
            counts[path] = live.filter { $0 == identity }.count
        }
        return counts
    }

    private func eventOnlyDescriptorIdentities() throws -> [WatcherIdentity] {
        let availableBytes = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        guard availableBytes >= 0 else { throw POSIXError(.EIO) }
        var fds = [proc_fdinfo](
            repeating: proc_fdinfo(), count: Int(availableBytes) / MemoryLayout<proc_fdinfo>.size + 64
        )
        let usedBytes = fds.withUnsafeMutableBytes {
            proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard usedBytes >= 0, Int(usedBytes) < fds.count * MemoryLayout<proc_fdinfo>.size else {
            throw POSIXError(.EOVERFLOW)
        }
        var identities: [WatcherIdentity] = []
        for index in 0 ..< Int(usedBytes) / MemoryLayout<proc_fdinfo>.size {
            let descriptor = fds[index].proc_fd
            guard fcntl(descriptor, F_GETFL) & O_EVTONLY == O_EVTONLY else { continue }
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { continue }
            identities.append(WatcherIdentity(device: info.st_dev, inode: info.st_ino))
        }
        return identities
    }

    private func processWakeups() throws -> (interrupt: UInt64, platformIdle: UInt64) {
        var info = task_power_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_power_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw POSIXError(.EIO) }
        return (info.task_interrupt_wakeups, info.task_platform_idle_wakeups)
    }
}

private extension ExternalFileWindowOccupancyTests {
    func requireWatcherTransition(
        retired: WatcherIdentity, source: URL, directory: URL, stage: String
    ) async throws {
        try await waitUntil(.seconds(5), "\(stage) retires and reattaches file watcher") {
            guard let live = try? eventOnlyDescriptorIdentities(),
                  let counts = try? watcherDescriptors(for: [source, directory])
            else { return false }
            return !live.contains(retired) && counts[source.path] == 1 && counts[directory.path] == 1
        }
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let defaults: UserDefaults
    let recovery: RecoveryBuffer
    let coordinator: WindowCoordinator

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: "external-window-\(UUID().uuidString)"))
        recovery = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json")),
            recoveryBuffer: recovery,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
    }

    func makeWindow(model: WorkspaceModel) -> WindowController {
        WindowController(
            model: model, coordinator: coordinator, themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: coordinator.fileTreePreferences,
            initialContentController: NSViewController()
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
