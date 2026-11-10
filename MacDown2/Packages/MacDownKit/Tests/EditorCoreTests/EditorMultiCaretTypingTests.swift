import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("EditorTextSystem synthetic multi-caret typing")
struct EditorMultiCaretTypingTests {
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
}
