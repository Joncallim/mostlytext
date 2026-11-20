import AppKit
import Foundation
@testable import Highlighting
import Testing

/// Runs the original four real editor operations against controlled idle time.
@MainActor
final class RestoreIdleEditSequence {
    private let editor: HighlightedEditor
    private let sleeper: ManualRestoreSleeper
    private let idle = SizeFallbackFixtures.policy.restoreIdleDelay
    private var waiterID: Int?
    private var activeTask: Task<Void, Never>?
    private var restoreTasks: [Task<Void, Never>] = []
    private var tasksByID: [Int: Task<Void, Never>] = [:]
    private var lastEditStarted = Duration.zero
    private var checksWhileNotIdle = 0
    private var wasReducedAfterLastEdit = true
    private var timeline: [String] = []

    init(editor: HighlightedEditor, sleeper: ManualRestoreSleeper) {
        self.editor = editor
        self.sleeper = sleeper
        editor.highlighter.restoreSleep = sleeper.sleepClosure
        let toDelete = editor.length - SizeFallbackFixtures.policy.restoreAtOrBelowUTF16Units
        editor.paste("", over: NSRange(location: 100, length: toDelete))
    }

    func run(includesIdlePause: Bool) async {
        #expect(editor.mode == .reducedForTestPolicy)
        guard let firstID = await sleeper.waitForAllocation(after: 0),
              await sleeper.waitForRegistration(firstID)
        else {
            Issue.record("initial restore sleep did not allocate and register before the deadlock guard")
            await drainTasks()
            return
        }
        #expect(sleeper.deadline(for: firstID) == idle)
        waiterID = firstID
        activeTask = editor.highlighter.restoreTask
        if let activeTask {
            restoreTasks.append(activeTask)
            tasksByID[firstID] = activeTask
        }

        for index in 0 ..< 4 {
            guard await performEdit(index: index, includesIdlePause: includesIdlePause) else {
                await drainTasks()
                return
            }
        }
        if activeTask != nil, let waiterID {
            let released = sleeper.advance(by: idle)
            await joinReleased(released)
            #expect(sleeper.completedIDs.contains(waiterID))
        }
        #expect(checksWhileNotIdle >= 1, "every pause exceeded the idle delay; early-restore check never ran")
        await drainTasks()
    }

    private func performEdit(index: Int, includesIdlePause: Bool) async -> Bool {
        let pause = Duration.milliseconds(includesIdlePause && index == 2 ? 300 : 100)
        let released = sleeper.advance(by: pause)
        await joinReleased(released)
        checkPause(index: index, includesIdlePause: includesIdlePause, released: released)

        let modeBeforeEdit = editor.mode
        lastEditStarted = sleeper.now
        let obsoleteTask = activeTask
        let obsoleteWaiterID = waiterID
        let allocationCount = sleeper.allocatedIDs.count
        editor.typeOrDelete(at: 50, insert: index.isMultiple(of: 2))
        #expect(editor.mode == modeBeforeEdit, "a small edit neither restores nor reduces highlighting")
        wasReducedAfterLastEdit = editor.mode == .reducedForTestPolicy
        guard await registerReplacement(after: allocationCount) else { return false }
        await releaseObsoleteWaiter(obsoleteTask, id: obsoleteWaiterID)
        return true
    }

    private func checkPause(index: Int, includesIdlePause: Bool, released: [Int]) {
        if includesIdlePause, index == 2, let waiterID {
            #expect(released.contains(waiterID), "the waiter released at the controlled idle deadline")
        }
        if let waiterID, released.contains(waiterID), sleeper.now - lastEditStarted >= idle {
            #expect(editor.mode == .full, "eligible restore completed after its full idle deadline")
        }
        if !released.isEmpty {
            activeTask = nil
            waiterID = nil
        }
        if wasReducedAfterLastEdit, sleeper.now - lastEditStarted < idle {
            checksWhileNotIdle += 1
            #expect(editor.mode == .reducedForTestPolicy, "restored before an idle delay had elapsed")
        }
        timeline.append(
            "pause \(index): elapsed=\(sleeper.now - lastEditStarted), mode=\(editor.mode), "
                + "revision=\(editor.system.contentRevision), generation=\(editor.highlighter.generation), "
                + "tokens=\(editor.highlighter.styledTokenCount)"
        )
    }

    private func registerReplacement(after allocationCount: Int) async -> Bool {
        guard wasReducedAfterLastEdit,
              editor.length <= SizeFallbackFixtures.policy.restoreAtOrBelowUTF16Units
        else {
            waiterID = nil
            activeTask = nil
            return true
        }
        guard let nextID = await sleeper.waitForAllocation(after: allocationCount),
              await sleeper.waitForRegistration(nextID)
        else {
            Issue.record("replacement restore sleep did not register before the deadlock guard")
            return false
        }
        #expect(sleeper.deadline(for: nextID) == sleeper.now + idle)
        waiterID = nextID
        activeTask = editor.highlighter.restoreTask
        if let activeTask {
            restoreTasks.append(activeTask)
            tasksByID[nextID] = activeTask
        }
        return true
    }

    private func releaseObsoleteWaiter(_ task: Task<Void, Never>?, id: Int?) async {
        guard let task, let id else { return }
        #expect(sleeper.release(id), "canceled registered waiter is held for controlled completion")
        await task.value
        #expect(editor.mode == .reducedForTestPolicy)
        if let waiterID {
            #expect(waiterID != id, "registered canceled waiter has a distinct live replacement")
            #expect(sleeper.registeredIDs.contains(waiterID))
            #expect(editor.highlighter.restoreTask != nil, "obsolete completion leaves its replacement active")
        }
    }

    private func joinReleased(_ ids: [Int]) async {
        for id in ids {
            guard let task = tasksByID[id] else {
                Issue.record("released restore waiter \(id) has no captured task handle")
                continue
            }
            await task.value
            #expect(sleeper.completedIDs.contains(id), "released waiter \(id) completed before the next edit")
        }
    }

    private func drainTasks() async {
        var tasks = restoreTasks
        if let current = editor.highlighter.restoreTask {
            tasks.append(current)
        }
        await sleeper.terminateAndDrain(tasks)
    }
}

/// Small cut-offs so the size fallback can be exercised quickly in Debug; the
/// shipped Markdown cut-off is measured separately in Release
/// (`HighlightBudgetBenchmarkTests`).
enum SizeFallbackFixtures {
    static let policy = HighlightingSizePolicy(
        reduceAboveUTF16Units: 6000,
        restoreAtOrBelowUTF16Units: 4500,
        restoreIdleDelay: .milliseconds(200)
    )

    static func markdownOnly(_ languageID: String?) -> HighlightingSizePolicy? {
        languageID == "markdown" ? policy : nil
    }

    /// Markdown (headings, inline markup, lists, fences) of exactly `units`
    /// UTF-16 code units.
    static func markdown(units: Int) -> String {
        let text = StallFixtures.markdown(utf8Bytes: units + 512)
        return (text as NSString).substring(to: units)
    }

    @MainActor
    static func editor(units: Int) -> HighlightedEditor {
        HighlightedEditor(text: markdown(units: units), sizePolicy: markdownOnly)
    }
}

/// Stands in for Neon's storage delegate behind the gate and records which
/// character edits reached it, forwarding them so Neon keeps working.
final class RecordingStorageDelegate: NSObject, NSTextStorageDelegate {
    private weak var downstream: NSTextStorageDelegate?
    private(set) var willCount = 0
    private(set) var didCount = 0
    var onWillCharacterEdit: (() -> Void)?
    var onDidCharacterEdit: (() -> Void)?

    init(downstream: NSTextStorageDelegate) {
        self.downstream = downstream
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedCharacters) {
            willCount += 1
            onWillCharacterEdit?()
        }
        downstream?.textStorage?(textStorage, willProcessEditing: editedMask, range: editedRange, changeInLength: delta)
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedCharacters) {
            didCount += 1
            onDidCharacterEdit?()
        }
        downstream?.textStorage?(textStorage, didProcessEditing: editedMask, range: editedRange, changeInLength: delta)
    }
}

extension HighlightedEditor {
    var mode: HighlightingState.Mode {
        highlighter.state.mode
    }

    var neonIsAttached: Bool {
        highlighter.highlighter != nil
    }

    var storage: NSTextStorage {
        textView.textStorage ?? NSTextStorage()
    }

    /// No highlighter-owned rendering attribute anywhere: plain presentation.
    var isPlain: Bool {
        renderedRuns().isEmpty
    }

    /// Lets queued main-queue work (deferred presentation clearing, Neon's
    /// `endBuffering`) and short tasks run.
    func settle(_ duration: Duration = .milliseconds(150)) async {
        try? await Task.sleep(for: duration)
    }

    /// Polls for an eventual transition without assuming the scheduler resumes it within a fixed sleep.
    /// Tests of the minimum idle delay must separately assert that restoration cannot happen too early.
    func waitUntil(_ timeout: Duration = .seconds(15), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Replaces `range` as a paste does, then closes the undo group.
    func paste(_ text: String, over range: NSRange) {
        textView.insertText(text, replacementRange: range)
        textView.breakUndoCoalescing()
    }

    func insert(_ text: String, at location: Int) {
        paste(text, over: NSRange(location: location, length: 0))
    }

    var length: Int {
        (textView.string as NSString).length
    }
}

extension HighlightingState.Mode {
    static let reducedForTestPolicy = HighlightingState.Mode.reduced(
        .documentTooLarge(limitUTF16Units: SizeFallbackFixtures.policy.reduceAboveUTF16Units)
    )
}
