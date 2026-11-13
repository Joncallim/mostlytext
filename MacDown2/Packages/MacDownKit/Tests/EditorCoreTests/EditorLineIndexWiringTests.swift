import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 2a — proves `EditorTextSystem.lineIndex` stays correct
/// across every real, AppKit-driven edit path, not just the pure
/// `EditorLineIndex.applying(...)` unit tests. Each test compares the
/// system's live (incrementally updated) index against a fresh full
/// rebuild of the resulting text -- the same equivalence style
/// `EditorLineIndexTests.assertIncrementalMatchesRebuild` uses, but driven
/// through real `NSTextView` editing rather than calling `applying`
/// directly, so a wiring mistake here (e.g. missing a delegate hook, or a
/// stale `pendingLineIndexEdit`) is caught even if the pure type itself is
/// correct.
@MainActor
@Suite("EditorLineIndex wiring")
struct EditorLineIndexWiringTests {
    private let support = EditingAssistIntegrationSupport.self

    private struct PreEditObservation {
        let range: NSRange
        let replacement: String
        let oldLength: Int
        let oldWord: String
    }

    private func assertMatchesFreshRebuild(
        _ system: EditorTextSystem,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let rebuilt = EditorLineIndex(text: system.text as NSString)
        #expect(
            system.lineIndex == rebuilt,
            "system.lineIndex diverged from a fresh rebuild",
            sourceLocation: sourceLocation
        )
    }

    @Test func initialLineIndexMatchesInitialText() {
        let system = support.makeSystem(text: "line1\nline2\nline3")
        assertMatchesFreshRebuild(system)
    }

    @Test func plainTypingUpdatesLineIndexIncrementally() {
        let system = support.makeSystem(text: "hello world")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        // Simulates real typed input: AppKit's own insertText(_:) path,
        // which triggers shouldChangeTextIn/textDidChange exactly as a
        // genuine keystroke would.
        system.textView.setSelectedRange(NSRange(location: 5, length: 0))
        system.textView.insertText("\n-- inserted --\n", replacementRange: NSRange(location: 5, length: 0))

        assertMatchesFreshRebuild(system)
    }

    @Test func preEditObserverSeesOldUTF16SourceBeforeAppKitMutation() {
        let original = "alpha 😀\r\nbeta"
        let system = support.makeSystem(text: original)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)
        let target = (original as NSString).range(of: "beta")
        var observed: PreEditObservation?
        system.preEditObserver = { range, replacement, oldSource in
            observed = PreEditObservation(range: range, replacement: replacement,
                                          oldLength: oldSource.length, oldWord: oldSource.substring(with: range))
        }

        system.textView.insertText("gamma", replacementRange: target)

        #expect(observed?.range == target)
        #expect(observed?.replacement == "gamma")
        #expect(observed?.oldLength == (original as NSString).length)
        #expect(observed?.oldWord == "beta")
        #expect(system.text == "alpha 😀\r\ngamma")
        assertMatchesFreshRebuild(system)
    }

    /// An IME / dead-key composition posts no `didChange` for its marked-text edits, so the index never saw
    /// them and the commit's edit was applied to a stale index (wrong line starts; Delete Line then removed
    /// the wrong text, and a later edit could scan out of bounds).
    @Test func aDeadKeyCompositionKeepsTheLineIndexCorrect() {
        let text = (1 ... 10).map { "line \($0)" }.joined(separator: "\n")
        let system = support.makeSystem(text: text)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)
        system.textView.setSelectedRange(NSRange(location: 6, length: 0))

        system.textView.setMarkedText(
            "´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(
                location: NSNotFound,
                length: 0
            )
        )
        system.textView.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))

        assertMatchesFreshRebuild(system)
    }

    @Test func aMultiCharacterCompositionKeepsTheLineIndexCorrect() {
        let system = support.makeSystem(text: "a\nb\nc")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)
        system.textView.setSelectedRange(NSRange(location: 1, length: 0))

        system.textView.setMarkedText(
            "ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(
                location: NSNotFound,
                length: 0
            )
        )
        system.textView.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))

        assertMatchesFreshRebuild(system)
    }

    @Test func multipleSequentialEditsKeepLineIndexCorrect() {
        let system = support.makeSystem(text: "a\nb\nc")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.textView.insertText("\nnew", replacementRange: NSRange(location: 1, length: 0))
        assertMatchesFreshRebuild(system)

        system.textView.insertText("start\n", replacementRange: NSRange(location: 0, length: 0))
        assertMatchesFreshRebuild(system)

        system.textView.insertText("\r\n", replacementRange: NSRange(location: system.text.utf16.count, length: 0))
        assertMatchesFreshRebuild(system)
    }

    @Test func multiRangeTransactionUpdatesLineIndexForEveryRange() {
        let system = support.makeSystem(text: "cat\ncat\ncat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.apply(EditorEditTransaction(replacements: [
            TextReplacement(range: NSRange(location: 0, length: 3), replacementText: "dog\ndog"),
            TextReplacement(range: NSRange(location: 4, length: 3), replacementText: "dog"),
            TextReplacement(range: NSRange(location: 8, length: 3), replacementText: "dog\ndog"),
        ]))

        assertMatchesFreshRebuild(system)
    }

    @Test func assistInterceptedEditUpdatesLineIndexToTheAssistsActualEdit() {
        // A Markdown command (E10's `performMarkdownCommand`) intercepts and
        // replaces via `applyAssistOutcome`'s nested `insertText` call --
        // never through the "outer" shouldChangeTextIn path at all, since
        // this isn't triggered by typing. Proves the line index reflects
        // the assist's real edit, not a stale/uncaptured state.
        let system = support.makeMarkdownSystem(text: "hello")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.textView.setSelectedRange(NSRange(location: 0, length: 5))
        _ = system.performMarkdownCommand(.bold)

        assertMatchesFreshRebuild(system)
    }

    @Test func undoAndRedoKeepLineIndexCorrect() {
        let system = support.makeSystem(text: "one\ntwo\nthree")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        system.textView.insertText(
            "\nfour\nfive",
            replacementRange: NSRange(location: system.text.utf16.count, length: 0)
        )
        assertMatchesFreshRebuild(system)

        system.undoManager.undo()
        assertMatchesFreshRebuild(system)

        system.undoManager.redo()
        assertMatchesFreshRebuild(system)
    }

    @Test func setTextRebuildsLineIndex() {
        let system = support.makeSystem(text: "a\nb")
        system.setText("x\ny\nz\nw")
        assertMatchesFreshRebuild(system)
    }

    @Test func replaceTextFromExternalRebuildsLineIndex() {
        let system = support.makeSystem(text: "a\nb\nc")
        let snapshot = system.viewportSnapshot()
        system.replaceTextFromExternal("x\ny", preserving: snapshot, clearUndo: true)
        assertMatchesFreshRebuild(system)
    }

    @Test func editWithoutACoordinatorDoesNotCrashButLeavesTheIndexUnwired() {
        // Documents the honest limitation: the incremental hook lives in
        // `EditorView.Coordinator` (production always attaches one via
        // `EditorView.makeNSView`); without one, `shouldChangeTextIn`/
        // `textDidChange` never fire at all (no delegate to call), so the
        // index is never told about the edit. Not a bug -- `setText`/
        // `replaceTextFromExternal` are always available as an explicit
        // full-rebuild escape hatch -- but worth pinning so a future
        // refactor that moves this hook doesn't silently assume otherwise.
        let system = support.makeSystem(text: "hello")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.textView.insertText(" world", replacementRange: NSRange(location: 5, length: 0))

        #expect(system.text == "hello world")
        #expect(system.lineIndex != EditorLineIndex(text: system.text as NSString))
    }

    @Test func multiRangeTransactionLeavesLineIndexMatchingARebuild() {
        let system = support.makeSystem(text: "a\nb\nc\nd\n")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)

        // Net length change is zero, so a stale index would pass the length-consistency check.
        system.apply(EditorEditTransaction(replacements: [
            TextReplacement(range: NSRange(location: 0, length: 1), replacementText: "x\ny"),
            TextReplacement(range: NSRange(location: 2, length: 1), replacementText: "q"),
            TextReplacement(range: NSRange(location: 4, length: 1), replacementText: ""),
            TextReplacement(range: NSRange(location: 6, length: 1), replacementText: "z"),
        ]))

        assertMatchesFreshRebuild(system)
    }

    @Test func largeMultiRangeTransactionReportsEveryRangeButRebuildsTheLineIndexOnce() {
        let text = (0 ..< 2000).map { "line \($0) cat" }.joined(separator: "\n")
        let system = support.makeSystem(text: text)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)
        let source = text as NSString
        var replacements: [TextReplacement] = []
        var search = NSRange(location: 0, length: source.length)
        while true {
            let found = source.range(of: "cat", range: search)
            guard found.location != NSNotFound else { break }
            replacements.append(TextReplacement(range: found, replacementText: "dog"))
            search = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
        }
        var changes: [EditorTextChange] = []
        system.textChangeObserver = { changes.append($0) }

        system.apply(EditorEditTransaction(replacements: replacements))

        // Per-range patches each copy the whole line array (quadratic across a Replace All), but observers still get
        // one `.edit` per range, highest offset first, so the Find model's search domain survives.
        #expect(changes.count == replacements.count)
        #expect(!changes.contains(.untracked))
        #expect(changes.first == .edit(range: replacements.last?.range ?? NSRange(), replacementLength: 3))
        #expect(system.text.hasSuffix("line 1999 dog"))
        assertMatchesFreshRebuild(system)
    }

    /// A spliced transaction (above `spliceThreshold`) must produce exactly the text the per-range path would, undo as
    /// one step, and keep untouched text between the matches byte-for-byte.
    @Test func aSplicedTransactionMatchesThePerRangeResultAndUndoesAsOneStep() {
        let original = (0 ..< 500).map { "row \($0) cat\r\nplain \($0)" }.joined(separator: "\n")
        let system = support.makeSystem(text: original)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)
        let source = original as NSString
        var replacements: [TextReplacement] = []
        var search = NSRange(location: 0, length: source.length)
        while true {
            let found = source.range(of: "cat", range: search)
            guard found.location != NSNotFound else { break }
            replacements.append(TextReplacement(range: found, replacementText: "wolf\nfox"))
            search = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
        }
        #expect(replacements.count > EditorTextSystem.spliceThreshold)

        system.apply(EditorEditTransaction(replacements: replacements, undoActionName: "Replace All"))

        #expect(system.text == original.replacingOccurrences(of: "cat", with: "wolf\nfox"))
        assertMatchesFreshRebuild(system)
        system.undoManager.undo()
        #expect(system.text == original)
    }

    @Test func aLargeTransactionIsNotQuadratic() {
        let text = (0 ..< 20000).map { "line \($0) cat" }.joined(separator: "\n")
        let system = support.makeSystem(text: text)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        _ = support.makeCoordinator(system: system)
        let source = text as NSString
        var replacements: [TextReplacement] = []
        var search = NSRange(location: 0, length: source.length)
        while true {
            let found = source.range(of: "cat", range: search)
            guard found.location != NSNotFound else { break }
            replacements.append(TextReplacement(range: found, replacementText: "dog"))
            search = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
        }
        let start = ContinuousClock.now

        system.apply(EditorEditTransaction(replacements: replacements))

        // 20k per-range inserts took ~4.7 s; the spliced edit is a single native replacement.
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(system.text.hasSuffix("line 19999 dog"))
    }
}
