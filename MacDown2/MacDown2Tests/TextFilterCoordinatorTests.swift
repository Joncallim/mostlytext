import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextFilters
import Themes
import Workspace

/// App-target integration coverage for `TextFilterCoordinator` against a
/// real `EditorTextSystem`/`WindowController` — the gap the post-review
/// adversarial pass identified as finding #12: the previous suite only
/// exercised the pure `clampedRange` helper (now folded into
/// `EditorTextSystem.applyExternalReplacement`) and never ran a filter
/// through the coordinator against a live editor, so the mutation/undo/
/// fidelity/staleness/lifecycle paths below were unverified.
@MainActor
@Suite("TextFilterCoordinator")
struct TextFilterCoordinatorTests {
    // MARK: - Fixture plumbing

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeCommand(_ script: String, in directory: URL) throws -> TextFilterCommand {
        let name = "\(UUID().uuidString).sh"
        let url = directory.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return TextFilterCommand(id: name, name: name, executableURL: url)
    }

    /// A slow script the test can hold open across an intervening edit or a
    /// window close, then release by writing a sentinel file.
    static func makeGatedCommand(gate: URL, in directory: URL) throws -> TextFilterCommand {
        try makeCommand(
            """
            #!/bin/sh
            while [ ! -f "\(gate.path)" ]; do sleep 0.02; done
            cat | tr 'a-z' 'A-Z'
            """,
            in: directory
        )
    }

    struct Fixture {
        let coordinator: WindowCoordinator
        let controller: WindowController
        let tabID: UUID
    }

    static func target(
        controller: WindowController, tabID: UUID
    ) throws -> TextFilterCoordinator.TextFilterEditingTarget {
        let textSystem = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        let document = try #require(controller.model.tabStore.tabs.first { $0.id == tabID }).document
        return TextFilterCoordinator.TextFilterEditingTarget(
            controller: controller,
            tabID: tabID,
            textSystem: textSystem,
            documentURL: document.fileURL,
            documentGeneration: document.mutationGeneration
        )
    }

    // MARK: - End-to-end mutation/undo (J4, finding #12)

    @Test func selectionReplacementAppliesExactlyOneUndoStep() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3)) // "two"
        let command = try Self.makeCommand("#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "one TWO")
        #expect(textSystem.undoManager.canUndo)
        textSystem.undoManager.undo()
        #expect(textSystem.text == "one two")
    }

    @Test func wholeDocumentReplacementAppliesExactlyOneUndoStep() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one\ntwo\n")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 0)) // empty selection: whole document
        let command = try Self.makeCommand("#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "ONE\nTWO\n")
        textSystem.undoManager.undo()
        #expect(textSystem.text == "one\ntwo\n")
    }

    /// Post-review finding #14: the manual matrix previously claimed empty
    /// stdout was an error, contradicting the implemented zero-exit/empty-
    /// output semantics. This is the explicit test the finding asked for.
    @Test func zeroExitEmptyStdoutDeletesSelectionAsOneUndoableEdit() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3))
        let command = try Self.makeCommand("#!/bin/sh\ntrue\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "one ")
        textSystem.undoManager.undo()
        #expect(textSystem.text == "one two")
    }

    // MARK: - Editing-assist fidelity (finding #3)

    /// Before the `applyExternalReplacement` seam, a filter's literal `*`
    /// output was reinterpreted by the Markdown editing-assist engine as a
    /// bold/italic delimiter and expanded to `*foo*` instead of being
    /// inserted verbatim.
    @Test func filterOutputIsInsertedVerbatimEvenWhenMarkdownAssistsAreEnabled() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "foo")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.apply(EditorConfiguration(
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            editingAssists: .markdownDefault
        ))
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 3)) // "foo"
        let command = try Self.makeCommand("#!/bin/sh\ncat >/dev/null\nprintf '*'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        await fixture.coordinator.textFilterCoordinator.run(command, against: target)

        #expect(textSystem.text == "*")
        #expect(textSystem.undoManager.canUndo)
        textSystem.undoManager.undo()
        #expect(textSystem.text == "foo")
    }

    // MARK: - Stale-completion rejection (finding #1)

    @Test func aLiveEditWhileTheFilterIsRunningDiscardsTheStaleResultWithoutMutation() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 4, length: 3)) // "two"
        let command = try Self.makeGatedCommand(gate: gate, in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let runTask = Task {
            await fixture.coordinator.textFilterCoordinator.run(command, against: target)
        }
        // Let the filter actually launch and block on the gate before editing.
        try await Task.sleep(for: .milliseconds(100))

        // Simulate a live edit through the real, delegate-wired text view —
        // exactly like the user typing while the filter runs.
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 0))
        textSystem.textView.insertText("X ", replacementRange: NSRange(location: 0, length: 0))
        let liveTextAfterEdit = textSystem.text

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await runTask.value

        // The stale completion must not have touched the text the live edit
        // produced, and must not have added an undo entry of its own.
        #expect(textSystem.text == liveTextAfterEdit)
    }

    // MARK: - Task ownership / window-close cancellation (finding #5)

    @Test func closingTheWindowCancelsARunningFilterAndDiscardsItsResult() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let command = try Self.makeGatedCommand(gate: gate, in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let runTask = Task {
            await fixture.coordinator.textFilterCoordinator.run(command, against: target)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!fixture.controller.textFilterTaskHandles.isEmpty)

        fixture.controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(fixture.controller.textFilterTaskHandles.isEmpty)

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await runTask.value

        // The editor was evicted by `windowWillClose`; a late completion has
        // nothing live to mutate.
        #expect(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString) == nil)
    }

    @Test func aNewRunSupersedesAndCancelsThePreviousOneForTheSameTab() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let fixture = try Self.makeController(text: "one two")
        let textSystem = try #require(fixture.controller.editorStore.existingSystem(for: fixture.tabID.uuidString))
        textSystem.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let slowCommand = try Self.makeGatedCommand(gate: gate, in: directory)
        let fastCommand = try Self.makeCommand("#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)

        let firstRun = Task {
            await fixture.coordinator.textFilterCoordinator.run(slowCommand, against: target)
        }
        try await Task.sleep(for: .milliseconds(100))

        // The second run on the same tab supersedes the first.
        await fixture.coordinator.textFilterCoordinator.run(fastCommand, against: target)
        #expect(textSystem.text == "ONE TWO")

        try "go".write(to: gate, atomically: true, encoding: .utf8)
        await firstRun.value

        // The superseded run's (identical, coincidentally) output must not
        // have landed a second, redundant mutation on top of the winner's.
        #expect(textSystem.text == "ONE TWO")
    }

    // MARK: - No stale alert on a cancelled/superseded task (finding #7)

    private actor AlertSpy {
        private(set) var invocations: [(message: String, window: NSWindow)] = []

        func record(_: Error, _ commandName: String, _ window: NSWindow) {
            invocations.append((message: commandName, window: window))
        }

        var count: Int {
            invocations.count
        }

        var isEmpty: Bool {
            invocations.isEmpty
        }
    }

    /// The control case: a genuine failure on a task nobody cancelled must
    /// still surface the alert, sheeted on the *originating* window.
    @Test func genuineFailureOnALiveUncancelledTaskStillPresentsTheAlert() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.makeController(text: "one two")
        let command = try Self.makeCommand("#!/bin/sh\nexit 7\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)
        let spy = AlertSpy()
        let coordinator = TextFilterCoordinator(coordinator: fixture.coordinator) { error, name, window in
            await spy.record(error, name, window)
        }

        await coordinator.run(command, against: target)

        #expect(await spy.count == 1)
        let window = try #require(fixture.controller.window)
        #expect(await spy.invocations.first?.window === window)
    }

    /// Cancellation is a deliberate withdrawal and must stay silent. Use a
    /// gated command so this test cancels a run that is definitely still in
    /// flight instead of racing an immediate `exit 7` process that may have
    /// legitimately presented its failure before cancellation happens.
    @Test func windowCloseCancellationSurfacesNoAlert() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("window-close-alert-gate")
        let fixture = try Self.makeController(text: "one two")
        let command = try Self.makeGatedCommand(gate: gate, in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)
        let spy = AlertSpy()
        let coordinator = TextFilterCoordinator(coordinator: fixture.coordinator) { error, name, window in
            await spy.record(error, name, window)
        }

        let runTask = Task { await coordinator.run(command, against: target) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!fixture.controller.textFilterTaskHandles.isEmpty)
        fixture.controller.cancelAllTextFilterTasks()
        await runTask.value

        #expect(await spy.isEmpty, "a window-close cancellation must not surface an alert")
    }

    /// Same silent-withdrawal guarantee for supersession. The first command
    /// is held behind a gate, so the second run necessarily cancels an active
    /// predecessor rather than sometimes arriving after a fast failure has
    /// already completed and correctly presented its alert.
    @Test func supersedingAnInFlightRunSurfacesNoAlert() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("supersession-alert-gate")
        let fixture = try Self.makeController(text: "one two")
        let slowCommand = try Self.makeGatedCommand(gate: gate, in: directory)
        let supersedingCommand = try Self.makeCommand("#!/bin/sh\ncat\n", in: directory)
        let target = try Self.target(controller: fixture.controller, tabID: fixture.tabID)
        let spy = AlertSpy()
        let coordinator = TextFilterCoordinator(coordinator: fixture.coordinator) { error, name, window in
            await spy.record(error, name, window)
        }

        let firstRun = Task { await coordinator.run(slowCommand, against: target) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!fixture.controller.textFilterTaskHandles.isEmpty)
        // A second run on the same tab supersedes (cancels) the first via
        // the normal `registerTextFilterTask` path.
        await coordinator.run(supersedingCommand, against: target)
        await firstRun.value

        #expect(await spy.isEmpty, "a superseded in-flight task must not surface an alert")
    }
}
