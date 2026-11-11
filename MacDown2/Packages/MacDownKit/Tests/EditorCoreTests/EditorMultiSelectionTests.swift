import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3a — multi-selection typing/delete/paste routed through
/// `EditorEditTransaction`, and Escape-collapse (§6.9, §7.1, §7.2). Mounted
/// against a real `NSTextView`/window, matching `EditorEditTransactionTests`'
/// existing integration style. `EditorTextSystem.selectionSet`'s own
/// getter/setter/cache-invalidation contract has its own dedicated suite,
/// `EditorSelectionSetCacheTests.swift` (split out to keep this file under
/// its line-count limit).
///
/// The original scenarios below use genuine, non-zero-length selections.
/// `NSTextView.selectedRanges` collapses multiple bare carets or mixed
/// selected/bare ranges to one; `EditorTextSystem.selectionSet` now retains
/// those synthetic carets. Their insertion regression lives in
/// `EditorMultiCaretTypingTests`.
///
/// Multi-selection typing/delete are exercised through the REAL
/// `EditorTextView.insertText(_:replacementRange:)`/`deleteBackward(_:)`
/// override path, not `NSTextViewDelegate`'s array-based
/// `shouldChangeTextInRanges:replacementStrings:`. That delegate method was
/// tried first and found, empirically, to never be invoked by ordinary
/// typing/backspace regardless of how many `selectedRanges` are active —
/// AppKit acts only on the primary selection for a plain keystroke and
/// never fans it out on its own — so `EditorTextSystem.applyMultiCursorInsert(_:)`/
/// `applyMultiCursorDeleteSelection()`, called directly from the view-level
/// override, are the real mechanism (see `EditorTextSystem+MultiCursor.swift`).
///
/// Paste is confirmed to terminate in the identical
/// `insertText(_:replacementRange:)` chokepoint typing does
/// (`pastingReplacesEveryActiveSelectionThroughTheRealPasteboard`), exercised
/// against the real system pasteboard with its prior contents saved and
/// restored around the call, so this test has no lasting effect on the
/// developer's actual clipboard.
@MainActor
@Suite("EditorTextSystem multi-selection (Slice 3a)")
struct EditorMultiSelectionTests {
    private let support = EditingAssistIntegrationSupport.self

    // MARK: - Multi-selection typing (§7.2)

    @Test func typingReplacesEveryActiveSelectionWithTheSameText() {
        // The realistic multi-selection scenario: three occurrences of
        // "cat" already selected (e.g. by a future Select-All-Occurrence),
        // typing "dog" replaces all three simultaneously.
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        system.textView.selectedRanges = [0, 4, 8].map { NSValue(range: NSRange(location: $0, length: 3)) }
        system.textView.insertText("dog", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "dog dog dog")
    }

    @Test func typingIsOneUndoStepAndOnePublicationAcrossThreeSelections() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.textView.delegate = coordinator
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        system.textView.selectedRanges = [0, 4, 8].map { NSValue(range: NSRange(location: $0, length: 3)) }
        system.textView.insertText("dog", replacementRange: NSRange(location: NSNotFound, length: 0))

        // Asserted before the undo/publication checks below: without this,
        // the test cannot distinguish "all three selections were replaced"
        // from "only the primary selection was replaced, which also
        // produces exactly one notification" -- a real gap an independent
        // review caught in this test's first version.
        #expect(system.text == "dog dog dog")
        #expect(
            counter.count == 1,
            "expected exactly one binding publication for a 3-selection keystroke, got \(counter.count)"
        )
        #expect(system.undoManager.canUndo)

        system.undoManager.undo()
        #expect(system.text == "cat cat cat")
    }

    @Test func resultingCaretsLandRightAfterEachReplacementAccountingForLengthShifts() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.textView.selectedRanges = [0, 4, 8].map { NSValue(range: NSRange(location: $0, length: 3)) }
        let handled = system.applyMultiCursorInsert("elephant")

        #expect(handled)
        #expect(system.text == "elephant elephant elephant")
        // `EditorEditTransaction.resultingCaretRanges` correctly computes
        // all three post-edit caret positions (accounting for each earlier
        // replacement's own +5 length delta -- "elephant" is 8 chars vs
        // "cat"'s 3). `textView.selectedRanges` itself still only ever
        // shows the first (three simultaneous zero-length carets cannot
        // coexist there any more than three simultaneous bare carets can —
        // §6.9's architecture-correction note), but `selectionSet` itself
        // (Slice 3b-i's fix to the getter/setter cache) now correctly
        // retains all three: `EditorTextView`'s own secondary-caret drawing
        // pass is what makes the other two visible.
        #expect(system.selectionSet.ranges == [
            NSRange(location: 8, length: 0),
            NSRange(location: 17, length: 0),
            NSRange(location: 26, length: 0),
        ])
        #expect(system.textView.selectedRanges.map(\.rangeValue) == [NSRange(location: 8, length: 0)])
    }

    @Test func deleteBackwardRemovesEveryActiveSelection() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        system.textView.selectedRanges = [0, 4, 8].map { NSValue(range: NSRange(location: $0, length: 3)) }
        system.textView.deleteBackward(nil)

        #expect(system.text == "  ")
    }

    @Test func deleteForwardRemovesEveryActiveSelection() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        system.textView.selectedRanges = [0, 4, 8].map { NSValue(range: NSRange(location: $0, length: 3)) }
        system.textView.deleteForward(nil)

        #expect(system.text == "  ")
    }

    @Test func pastingReplacesEveryActiveSelectionThroughTheRealPasteboard() {
        // This test's first version assumed `NSTextView.paste(_:)` shares
        // the plain `insertText` chokepoint typing does, and failed against
        // real AppKit: `paste(_:)` actually performs the edit as TWO
        // separate `insertText` calls (delete the selection(s), then insert
        // the pasted text), and the first call's own multi-range delete
        // collapses the selection to one caret before the second call ever
        // runs -- silently losing the paste at every selection but one. This
        // is what led to `EditorTextView.paste(_:)`'s own dedicated
        // override (reads the pasteboard and routes it through
        // `applyMultiCursorInsert(_:)` in one step, ahead of AppKit's
        // two-step sequence). Exercised against the REAL system pasteboard,
        // with a best-effort save/restore of its prior contents around the
        // call (every UTI representation of every item, restored in one
        // `writeObjects` call so a multi-item clipboard doesn't lose all but
        // the last) -- not an absolute guarantee: a process crash between
        // the save and the restore, however unlikely, would still leave the
        // pasteboard in this test's transient state.
        let pasteboard = NSPasteboard.general
        let savedItems: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                let restoredItems = savedItems.map { typesToData -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in typesToData {
                        item.setData(data, forType: type)
                    }
                    return item
                }
                pasteboard.writeObjects(restoredItems)
            }
        }

        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        pasteboard.clearContents()
        pasteboard.setString("dog", forType: .string)
        system.textView.selectedRanges = [0, 4, 8].map { NSValue(range: NSRange(location: $0, length: 3)) }
        system.textView.paste(nil)

        #expect(system.text == "dog dog dog")
    }

    @Test func singleSelectionTypingIsUnaffectedByTheMultiSelectionOverride() {
        // `applyMultiCursorInsert`/`DeleteSelection` return `false` for
        // fewer than two active selections, falling straight through to
        // `super` -- this is the regression guard that adding the override
        // didn't change ordinary, single-selection typing at all.
        let system = support.makeSystem(text: "hello world")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)

        system.textView.selectedRanges = [NSValue(range: NSRange(location: 6, length: 5))]
        system.textView.insertText("there", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "hello there")
    }

    // MARK: - Escape-collapse

    @Test func escapeCollapsesAMultiSelectionToItsPrimaryRange() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 1
        )

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        #expect(handled)
        #expect(!system.selectionSet.isMultiple)
        #expect(system.selectionSet.primaryRange == NSRange(location: 4, length: 3))
    }

    @Test func escapeFallsThroughToNativeHandlingWhenSelectionIsAlreadySingle() {
        let system = support.makeSystem(text: "one two three")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)

        system.selectedRange = NSRange(location: 0, length: 3)
        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        #expect(!handled, "Escape must fall through to AppKit's default handling when there is only one selection")
        #expect(system.selectedRange == NSRange(location: 0, length: 3))
    }

    // MARK: - IME safety (fail open)

    @Test func markedTextSessionBypassesMultiSelectionInsertEntirely() {
        let system = support.makeSystem(text: "hello world")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.textView.selectedRanges = [0, 6].map { NSValue(range: NSRange(location: $0, length: 5)) }
        system.textView.setMarkedText(
            "\u{3042}",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(system.textView.hasMarkedText())

        let handled = system.applyMultiCursorInsert("x")

        #expect(!handled, "an active IME composition must fail open to native handling, multi-selection or not")
    }

    @Test func markedTextSessionBypassesMultiSelectionDeleteEntirely() {
        let system = support.makeSystem(text: "hello world")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        system.textView.selectedRanges = [0, 6].map { NSValue(range: NSRange(location: $0, length: 5)) }
        system.textView.setMarkedText(
            "\u{3042}",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let handled = system.applyMultiCursorDeleteSelection()

        #expect(!handled, "an active IME composition must fail open to native handling, multi-selection or not")
    }
}
