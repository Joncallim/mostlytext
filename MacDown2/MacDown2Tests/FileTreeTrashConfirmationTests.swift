import FileTree
import Foundation
@testable import MacDown2
import Testing

@MainActor
struct FileTreeTrashConfirmationTests {
    @Test func confirmationUsesItsOriginalSourceEvenAfterSelectionChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.setRoot(fixture.firstRoot)
        let source = fixture.firstRoot.appendingPathComponent("original.md")
        let confirmation = FileTreeTrashConfirmation(model: fixture.model, source: source) { true }
        fixture.model.selectedURL = fixture.firstRoot.appendingPathComponent("later-selection.md")
        #expect(try await confirmation.run()?.url == source)
        #expect(await fixture.mutator.trashed == [source])
    }

    @Test func aChangedRootCannotRefreshAnOldConfirmation() async throws {
        try await assertStaleConfirmation(restore: false)
    }

    @Test func anABARootCannotRefreshAnOldConfirmation() async throws {
        try await assertStaleConfirmation(restore: true)
    }

    private func assertStaleConfirmation(restore: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.setRoot(fixture.firstRoot)
        let confirmation = FileTreeTrashConfirmation(
            model: fixture.model, source: fixture.firstRoot.appendingPathComponent("original.md")
        ) { true }
        await fixture.model.setRoot(fixture.secondRoot)
        if restore {
            await fixture.model.setRoot(fixture.firstRoot)
        }
        #expect(try await confirmation.run() == nil)
        #expect(await fixture.mutator.trashed.isEmpty)
    }

    @Test func aClosedOriginCannotPerformItsConfirmedOperation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.setRoot(fixture.firstRoot)
        var open = true
        let confirmation = FileTreeTrashConfirmation(
            model: fixture.model, source: fixture.firstRoot.appendingPathComponent("original.md")
        ) { open }
        open = false
        #expect(try await confirmation.run() == nil)
        #expect(await fixture.mutator.trashed.isEmpty)
    }

    @Test func aCancelledTaskCannotStartTheMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        await fixture.model.setRoot(fixture.firstRoot)
        let confirmation = FileTreeTrashConfirmation(
            model: fixture.model, source: fixture.firstRoot.appendingPathComponent("original.md")
        ) { true }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await confirmation.run()
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await fixture.mutator.trashed.isEmpty)
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let firstRoot: URL
        let secondRoot: URL
        let mutator = RecordingTrashMutator()
        let model: FileTreeModel

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("trash-confirm-\(UUID().uuidString)")
            firstRoot = root.appendingPathComponent("first")
            secondRoot = root.appendingPathComponent("second")
            try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
            model = FileTreeModel(
                reader: EmptyConfirmationReader(),
                mutator: mutator,
                watcher: NoConfirmationWatching(),
                preferences: FileTreePreferences(store: ConfirmationPreferences()),
                supportedExtensions: ["md"]
            )
        }

        func cleanup() {
            model.dispose()
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private actor RecordingTrashMutator: FileSystemMutating {
    private(set) var trashed: [URL] = []
    func itemKind(at _: URL) -> FileSystemItemKind? {
        .file
    }

    func trash(at url: URL) {
        trashed.append(url)
    }

    func createFile(at _: URL) throws {
        throw FileTreeOperationError.staleOperation
    }

    func createDirectory(at _: URL) throws {
        throw FileTreeOperationError.staleOperation
    }

    func move(from _: URL, to _: URL) throws {
        throw FileTreeOperationError.staleOperation
    }

    func copy(from _: URL, to _: URL) throws {
        throw FileTreeOperationError.staleOperation
    }
}

private struct EmptyConfirmationReader: DirectoryReading {
    func contents(of _: URL) -> [DirectoryEntry] {
        []
    }
}

private struct NoConfirmationWatching: DirectoryWatching {
    func watch(_: URL, onChange _: @escaping @Sendable (DirectoryWatchEvent) -> Void) -> any DirectoryWatcherHandle {
        NoConfirmationWatch()
    }
}

private struct NoConfirmationWatch: DirectoryWatcherHandle { func cancel() {} }

@MainActor
private final class ConfirmationPreferences: FileTreePreferenceStoring {
    var filter = FileTreeFilter()
    var opensOnSingleClick = false
    var recentRootBookmarks: [Data] = []
    var recentFileBookmarks: [Data] = []
}
