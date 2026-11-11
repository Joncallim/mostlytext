import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("EditorTextSystem multi-caret pairing")
struct EditorMultiCaretPairingTests {
    private func mountedMarkdown(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = EditingAssistIntegrationSupport.makeMarkdownSystem(text: text)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        return (system, window)
    }

    @Test func typingAnOpenerPairsAtBothBareCarets() {
        let (system, window) = mountedMarkdown("a b")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 0
        )

        system.textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "a() b()")
        #expect(system.selectionSet.ranges == [NSRange(location: 2, length: 0), NSRange(location: 6, length: 0)])
    }

    @Test func typingAnOpenerWrapsBothSelectedWords() {
        let (system, window) = mountedMarkdown("cat dog")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 1
        )

        system.textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "(cat) (dog)")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 3), NSRange(location: 7, length: 3)])
        #expect(system.selectionSet.primaryIndex == 1)
        system.undoManager.undo()
        #expect(system.text == "cat dog")
    }

    @Test func typingACloserSkipsBothExistingClosers() {
        let (system, window) = mountedMarkdown("() ()")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 1
        )

        system.textView.insertText(")", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "() ()")
        #expect(system.selectionSet.ranges == [NSRange(location: 2, length: 0), NSRange(location: 5, length: 0)])
        #expect(system.selectionSet.primaryIndex == 1)
    }

    @Test func typeOverAtOneCaretAndInsertionAtAnotherRemainIndependent() {
        let (system, window) = mountedMarkdown("() x")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        system.textView.insertText(")", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "() x)")
        #expect(system.selectionSet.ranges == [NSRange(location: 2, length: 0), NSRange(location: 5, length: 0)])
    }

    @Test func backspaceDeletesBothCompletedPairs() {
        let (system, window) = mountedMarkdown("() ()")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == " ")
        #expect(system.selectionSet.ranges == [NSRange(location: 0, length: 0), NSRange(location: 1, length: 0)])
        system.undoManager.undo()
        #expect(system.text == "() ()")
    }

    @Test func commandBackspaceUsesTheMultiCaretPathBeforePrimaryAssist() {
        let (system, window) = mountedMarkdown("() ()")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )
        let coordinator = system.textView.delegate as? EditorView.Coordinator

        let handled = coordinator?.textView(system.textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        #expect(handled == true)
        #expect(system.text == " ")
        #expect(system.selectionSet.count == 2)
    }

    @Test func generalTextDoesNotPairMarkdownDelimiterAtBareCarets() {
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .general
        let system = EditingAssistIntegrationSupport.makeSystem(text: "a b", configuration: configuration)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 0
        )

        system.textView.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "a* b*")
    }

    @Test func generalTextStillPairsStructuralOpenersAtBareCarets() {
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .general
        let system = EditingAssistIntegrationSupport.makeSystem(text: "a b", configuration: configuration)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 0
        )

        system.textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "a() b()")
        #expect(system.selectionSet.ranges == [NSRange(location: 2, length: 0), NSRange(location: 6, length: 0)])
    }

    @Test func oneHundredPairedCaretsKeepTheBoundedTransactionAndUndo() {
        let original = String(repeating: "x ", count: 100)
        let (system, window) = mountedMarkdown(original)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: (0 ..< 100).map { NSRange(location: $0 * 2 + 1, length: 0) },
            primaryIndex: 99
        )

        system.textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == String(repeating: "x() ", count: 100))
        #expect(system.selectionSet.ranges.map(\.location) == (0 ..< 100).map { $0 * 4 + 2 })
        #expect(system.selectionSet.primaryIndex == 99)
        system.undoManager.undo()
        #expect(system.text == original)
    }
}
