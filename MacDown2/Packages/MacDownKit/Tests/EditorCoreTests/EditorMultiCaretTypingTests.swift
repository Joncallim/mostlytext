import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("EditorTextSystem synthetic multi-caret typing")
struct EditorMultiCaretTypingTests {
    @Test func oneHundredTwentyEightBareCaretsUseSpliceWithoutLosingUndoOrPrimaryIdentity() {
        let original = String(repeating: "ab\n", count: 128)
        let system = EditingAssistIntegrationSupport.makeSystem(text: original)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)

        system.selectionSet = EditorSelectionSet(
            ranges: (0 ..< 128).map { NSRange(location: $0 * 3 + 1, length: 0) },
            primaryIndex: 97
        )
        #expect(system.selectionSet.count == 128)
        #expect(system.selectionSet.primaryIndex == 97)

        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))

        let expected = String(repeating: "aXb\n", count: 128)
        #expect(system.text == expected)
        #expect(system.selectionSet.count == 128)
        #expect(system.selectionSet.primaryIndex == 97)
        #expect(system.selectionSet.ranges == (0 ..< 128).map {
            NSRange(location: $0 * 4 + 2, length: 0)
        })

        #expect(system.undoManager.canUndo)
        system.undoManager.undo()
        #expect(system.text == original)
        #expect(system.undoManager.canRedo)
        system.undoManager.redo()
        #expect(system.text == expected)
    }

    @Test func twoBareCaretsInsertAtBothLocationsAndRemainAvailable() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "ab cd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )
        #expect(system.selectionSet.count == 2)
        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "aXb cXd")
        #expect(system.selectionSet.ranges == [
            NSRange(location: 2, length: 0),
            NSRange(location: 6, length: 0),
        ])
        system.textView.insertText("Y", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(system.text == "aXYb cXYd")
        #expect(system.selectionSet.ranges == [
            NSRange(location: 3, length: 0),
            NSRange(location: 8, length: 0),
        ])
    }

    @Test func aSelectedRangeAndABareCaretShareOneInsertTransaction() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "cat dog")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 7, length: 0)],
            primaryIndex: 1
        )
        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "X dogX")
        #expect(system.selectionSet.ranges == [
            NSRange(location: 1, length: 0),
            NSRange(location: 6, length: 0),
        ])
        #expect(system.selectionSet.primaryIndex == 1)
        #expect(system.undoManager.canUndo)
        system.undoManager.undo()
        #expect(system.text == "cat dog")
    }

    @Test func readOnlyTextDeclinesMultiCaretInsertAndDelete() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "cat dog")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)],
            primaryIndex: 0
        )
        system.textView.isEditable = false

        #expect(!system.applyMultiCursorInsert("X"))
        #expect(system.text == "cat dog")

        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 0
        )
        #expect(!system.applyMultiCursorDelete(.backward))
        #expect(system.text == "cat dog")
    }
}
