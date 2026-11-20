@testable import FileTree
import Foundation
import Testing

@MainActor
@Test func createCallerReceivesStaleResultAfterRootReplacement() async throws {
    let oldRoot = temporaryDirectory()
    let newRoot = temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: oldRoot)
        try? FileManager.default.removeItem(at: newRoot)
    }
    let mutator = SuspendedMutator(blocksMove: false)
    let model = FileTreeModel(
        reader: StaticReader(contents: [oldRoot: [], newRoot: []]),
        mutator: mutator,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(oldRoot)
    let task = Task { try await model.createFile(in: oldRoot) }
    var started = false
    for _ in 0 ..< 1000 {
        if await mutator.gate.hasStarted() {
            started = true
            break
        }
        await Task.yield()
    }
    #expect(started)
    await model.setRoot(newRoot)
    await mutator.gate.open()
    let result = try await task.value

    #expect(!result.isCurrent)
    #expect(model.root == newRoot.standardizedFileURL)
}

@MainActor
@Test func deleteRecreateReexpandRejectsTheOlderReloadCompletion() async {
    let root = URL(fileURLWithPath: "/tmp/reload-epoch-root", isDirectory: true)
    let child = root.appendingPathComponent("child", isDirectory: true)
    let reader = ReorderedRecreationReader(root: root, child: child)
    let model = FileTreeModel(
        reader: reader,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    let oldExpansion = Task { await model.expand(child) }
    await reader.waitForOlderReadStart()

    await model.rescanExpandedDirectories() // removes and evicts child
    await model.rescanExpandedDirectories() // recreates child at the same lexical URL

    let newExpansion = Task { await model.expand(child) }
    await newExpansion.value
    reader.releaseOlderRead()
    await oldExpansion.value

    #expect(model.rows.map(\.entry.name) == ["child", "fresh.md"])
}

@MainActor
@Test func queuedCreateContextRejectsBeforeStartAfterRootReplacement() async throws {
    let firstRoot = temporaryDirectory()
    let secondRoot = temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: firstRoot)
        try? FileManager.default.removeItem(at: secondRoot)
    }
    let mutator = SuspendedMutator(blocksMove: false)
    let model = FileTreeModel(
        reader: StaticReader(contents: [firstRoot: [], secondRoot: []]),
        mutator: mutator,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(firstRoot)
    let context = model.beginOperation()
    await model.setRoot(secondRoot)

    await #expect(throws: FileTreeOperationError.staleOperation) {
        try await model.createFile(in: firstRoot, context: context)
    }
    #expect(await !(mutator.gate.hasStarted()))
}

@MainActor
@Test func queuedMoveContextRejectsABARootReplacementBeforeStart() async throws {
    let firstRoot = temporaryDirectory()
    let secondRoot = temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: firstRoot)
        try? FileManager.default.removeItem(at: secondRoot)
    }
    let source = firstRoot.appendingPathComponent("source")
    let destination = firstRoot.appendingPathComponent("destination", isDirectory: true)
    let mutator = SuspendedMutator(blocksMove: true)
    let model = FileTreeModel(
        reader: StaticReader(contents: [
            firstRoot: [file(source), directory(destination)],
            secondRoot: [],
            destination: [],
        ]),
        mutator: mutator,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(firstRoot)
    let context = model.beginOperation()
    await model.setRoot(secondRoot)
    await model.setRoot(firstRoot)

    await #expect(throws: FileTreeOperationError.staleOperation) {
        try await model.move(source, intoDirectory: destination, context: context)
    }
    #expect(await !(mutator.gate.hasStarted()))
}

@MainActor
@Test func moveCallerReceivesStaleResultAfterRootReplacement() async throws {
    let oldRoot = temporaryDirectory()
    let newRoot = temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: oldRoot)
        try? FileManager.default.removeItem(at: newRoot)
    }
    let source = oldRoot.appendingPathComponent("source", isDirectory: true)
    let destination = oldRoot.appendingPathComponent("destination", isDirectory: true)
    let mutator = SuspendedMutator(blocksMove: true)
    let model = FileTreeModel(
        reader: StaticReader(contents: [
            oldRoot: [file(source), directory(destination)],
            destination: [],
            newRoot: [],
        ]),
        mutator: mutator,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(oldRoot)
    let task = Task { try await model.move(source, intoDirectory: destination) }
    var started = false
    for _ in 0 ..< 1000 {
        if await mutator.gate.hasStarted() {
            started = true
            break
        }
        await Task.yield()
    }
    #expect(started)
    await model.setRoot(newRoot)
    await mutator.gate.open()
    let result = try await task.value

    #expect(!result.isCurrent)
    #expect(model.root == newRoot.standardizedFileURL)
}

@MainActor
@Test func moveRejectsSymlinkedDescendantWithoutPartialMutation() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    let child = source.appendingPathComponent("child", isDirectory: true)
    let link = root.appendingPathComponent("alias", isDirectory: true)
    let marker = source.appendingPathComponent("marker.md")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: marker)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
    let model = FileTreeModel(
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    await #expect(throws: FileTreeOperationError.moveIntoOwnSubtree) {
        try await model.move(source, intoDirectory: link)
    }
    #expect(try Data(contentsOf: marker) == Data("keep".utf8))
    #expect(!FileManager.default.fileExists(atPath: child.appendingPathComponent("source").path))
}
