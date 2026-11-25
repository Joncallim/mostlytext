@testable import FileTree
import Foundation
import Testing

func directory(_ url: URL) -> DirectoryEntry {
    DirectoryEntry(url: url, isDirectory: true, isHidden: false, isPackage: false, isSymbolicLink: false)
}

func file(_ url: URL) -> DirectoryEntry {
    DirectoryEntry(url: url, isDirectory: false, isHidden: false, isPackage: false, isSymbolicLink: false)
}

func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

struct StaticReader: DirectoryReading {
    let contents: [URL: [DirectoryEntry]]

    func contents(of url: URL) throws -> [DirectoryEntry] {
        contents[url.standardizedFileURL] ?? []
    }
}

final class BlockingReader: @unchecked Sendable, DirectoryReading {
    let blockedURL: URL
    let release = DispatchSemaphore(value: 0)
    let contentsByURL: [URL: [DirectoryEntry]]
    let blockFirstReadOnly: Bool
    private let lock = NSLock()
    private var started = false
    private var blockedReads = 0

    var didStart: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }

    init(blockedURL: URL, contentsByURL: [URL: [DirectoryEntry]] = [:], blockFirstReadOnly: Bool = false) {
        self.blockedURL = blockedURL.standardizedFileURL
        self.contentsByURL = contentsByURL
        self.blockFirstReadOnly = blockFirstReadOnly
    }

    func contents(of url: URL) throws -> [DirectoryEntry] {
        let key = url.standardizedFileURL
        if key == blockedURL {
            lock.lock()
            blockedReads += 1
            let shouldBlock = !blockFirstReadOnly || blockedReads == 1
            if shouldBlock {
                started = true
            }
            lock.unlock()
            if shouldBlock {
                release.wait()
            }
        }
        return contentsByURL[key] ?? []
    }
}

final class FlakyReader: @unchecked Sendable, DirectoryReading {
    let root: URL
    let child: URL
    let sibling: URL
    private let lock = NSLock()
    private var childAttempts = 0

    init(root: URL, child: URL, sibling: URL) {
        self.root = root.standardizedFileURL
        self.child = child.standardizedFileURL
        self.sibling = sibling.standardizedFileURL
    }

    func contents(of url: URL) throws -> [DirectoryEntry] {
        if url.standardizedFileURL == root {
            return [directory(child), file(sibling)]
        }
        guard url.standardizedFileURL == child else { return [] }
        lock.lock(); defer { lock.unlock() }
        childAttempts += 1
        if childAttempts == 1 {
            throw CocoaError(.fileReadUnknown)
        }
        return [file(child.appendingPathComponent("recovered.md"))]
    }
}

final class RootFlakyReader: @unchecked Sendable, DirectoryReading {
    let root: URL
    private var attempts = 0

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func contents(of url: URL) throws -> [DirectoryEntry] {
        guard url.standardizedFileURL == root else { return [] }
        attempts += 1
        if attempts == 1 {
            throw CocoaError(.fileReadUnknown)
        }
        return []
    }
}

final class ReorderedRecreationReader: @unchecked Sendable, DirectoryReading {
    let root: URL
    let child: URL
    private let lock = NSLock()
    private let olderRead = DispatchSemaphore(value: 0)
    private var rootReads = 0
    private var childReads = 0
    private var olderReadStart: CheckedContinuation<Void, Never>?

    init(root: URL, child: URL) {
        self.root = root.standardizedFileURL
        self.child = child.standardizedFileURL
    }

    func contents(of url: URL) throws -> [DirectoryEntry] {
        let key = url.standardizedFileURL
        if key == root {
            lock.lock(); rootReads += 1
            let read = rootReads
            lock.unlock()
            return switch read {
            case 1, 3: [directory(child)]
            default: []
            }
        }
        guard key == child else { return [] }
        lock.lock(); childReads += 1
        let read = childReads
        let continuation = read == 1 ? olderReadStart : nil
        olderReadStart = nil
        lock.unlock()
        continuation?.resume()
        if read == 1 {
            olderRead.wait()
            return [file(child.appendingPathComponent("stale.md"))]
        }
        return [file(child.appendingPathComponent("fresh.md"))]
    }

    func waitForOlderReadStart() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if childReads > 0 {
                lock.unlock()
                continuation.resume()
            } else {
                olderReadStart = continuation
                lock.unlock()
            }
        }
    }

    func releaseOlderRead() {
        olderRead.signal()
    }
}

final class RaceCreatingMutator: @unchecked Sendable, FileSystemMutating {
    private var raced = false

    func mutate(_ operation: FileTreeMutation, authority _: FileTreeMutationAuthority) async throws {
        try await performInjectedMutation(operation, using: self)
    }

    func itemKind(at url: URL) async throws -> FileSystemItemKind? {
        url.lastPathComponent == "source" ? .file : .directory
    }

    func createFile(at url: URL) async throws {
        if !raced {
            raced = true
            try Data("race winner".utf8).write(to: url)
            throw POSIXError(.EEXIST)
        }
        try Data().write(to: url)
    }

    func createDirectory(at _: URL) async throws {}
    func move(from _: URL, to _: URL) async throws {}
    func copy(from _: URL, to _: URL) async throws {}
}

final class FolderRaceMutator: @unchecked Sendable, FileSystemMutating {
    private var raced = false

    func mutate(_ operation: FileTreeMutation, authority _: FileTreeMutationAuthority) async throws {
        try await performInjectedMutation(operation, using: self)
    }

    func itemKind(at _: URL) async throws -> FileSystemItemKind? {
        .directory
    }

    func createFile(at _: URL) async throws {}

    func createDirectory(at url: URL) async throws {
        if !raced {
            raced = true
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func move(from _: URL, to _: URL) async throws {}
    func copy(from _: URL, to _: URL) async throws {}
}

final class SuspendedMutator: @unchecked Sendable, FileSystemMutating {
    let blocksMove: Bool
    let gate = MutationGate()

    func mutate(_ operation: FileTreeMutation, authority _: FileTreeMutationAuthority) async throws {
        try await performInjectedMutation(operation, using: self)
    }

    init(blocksMove: Bool) {
        self.blocksMove = blocksMove
    }

    func itemKind(at url: URL) async throws -> FileSystemItemKind? {
        url.lastPathComponent == "source" ? .file : .directory
    }

    func createFile(at _: URL) async throws {
        await gate.wait()
    }

    func createDirectory(at _: URL) async throws {
        await gate.wait()
    }

    func move(from _: URL, to _: URL) async throws {
        if blocksMove {
            await gate.wait()
        }
    }

    func copy(from _: URL, to _: URL) async throws {}
}

/// Test doubles inject interleavings into the old operation-specific calls.
/// The shipping mutator has its own descriptor-rooted implementation.
private func performInjectedMutation(
    _ operation: FileTreeMutation, using mutator: any FileSystemMutating
) async throws {
    switch operation {
    case let .createFile(url): try await mutator.createFile(at: url)
    case let .createDirectory(url): try await mutator.createDirectory(at: url)
    case let .move(source, destination): try await mutator.move(from: source, to: destination)
    case let .copy(source, destination): try await mutator.copy(from: source, to: destination)
    }
}

actor MutationGate {
    private var started = false
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func hasStarted() -> Bool {
        started
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations = []
    }
}

struct TestWatching: DirectoryWatching {
    func watch(
        _: URL,
        onChange _: @escaping @Sendable (DirectoryWatchEvent) -> Void
    ) throws -> any DirectoryWatcherHandle {
        TestWatcher()
    }
}

final class RecordingWatching: @unchecked Sendable, DirectoryWatching {
    private let lock = NSLock()
    private var handles: [RecordingWatcher] = []

    var activeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return handles.filter { !$0.isCancelled }.count
    }

    var totalWatchCount: Int {
        lock.lock(); defer { lock.unlock() }
        return handles.count
    }

    func watch(
        _: URL,
        onChange _: @escaping @Sendable (DirectoryWatchEvent) -> Void
    ) throws -> any DirectoryWatcherHandle {
        let handle = RecordingWatcher()
        lock.lock(); handles.append(handle); lock.unlock()
        return handle
    }
}

final class RecordingWatcher: @unchecked Sendable, DirectoryWatcherHandle {
    private let lock = NSLock()
    private(set) var isCancelled = false

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        isCancelled = true
    }
}

final class TestWatcher: @unchecked Sendable, DirectoryWatcherHandle {
    func cancel() {}
}

@MainActor
final class MemoryPreferenceStore: FileTreePreferenceStoring {
    var filter = FileTreeFilter()
    var opensOnSingleClick = false
    var recentRootBookmarks: [Data] = []
    var recentFileBookmarks: [Data] = []
}
