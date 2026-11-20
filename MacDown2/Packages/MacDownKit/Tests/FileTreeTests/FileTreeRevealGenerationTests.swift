@testable import FileTree
import Foundation
import Testing

@MainActor
@Test func suspendedRevealCannotSelectAPathRepublishedByAReplacementRoot() async {
    let firstRoot = URL(fileURLWithPath: "/tmp/reveal-root", isDirectory: true)
    let otherRoot = URL(fileURLWithPath: "/tmp/reveal-other", isDirectory: true)
    let child = firstRoot.appendingPathComponent("nested", isDirectory: true)
    let target = child.appendingPathComponent("draft.md")
    let reader = BlockingReader(
        blockedURL: child,
        contentsByURL: [firstRoot: [directory(child)], child: [file(target)]],
        blockFirstReadOnly: true
    )
    let model = FileTreeModel(
        reader: reader, watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(firstRoot)

    let olderReveal = Task { await model.reveal(target) }
    for _ in 0 ..< 1000 where !reader.didStart {
        await Task.yield()
    }
    guard reader.didStart else {
        reader.release.signal()
        _ = await olderReveal.value
        Issue.record("the controlled old-root read did not start")
        return
    }
    await model.setRoot(otherRoot)
    await model.setRoot(firstRoot)
    await model.expand(child)
    #expect(model.rows.contains(where: { $0.entry.url == target }), "control: the new root published this path")
    #expect(model.selectedURL == nil)

    reader.release.signal()
    #expect(await olderReveal.value == false)
    #expect(model.selectedURL == nil)
}
