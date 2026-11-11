import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("EditorTextSystem synthetic multi-caret deletion")
struct EditorMultiCaretDeletionTests {
    private func mounted(_ text: String) -> EditorTextSystem {
        let system = EditingAssistIntegrationSupport.makeSystem(text: text)
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        return system
    }

    @Test func backspaceDeletesTheGraphemeBeforeEachBareCaret() {
        let system = mounted("ab cd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "b d")
        #expect(system.selectionSet.ranges == [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)])
        #expect(system.undoManager.canUndo)
        system.undoManager.undo()
        #expect(system.text == "ab cd")
        system.undoManager.redo()
        #expect(system.text == "b d")
    }

    @Test func forwardDeleteRemovesTheGraphemeAfterEachBareCaret() {
        let system = mounted("ab cd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 1
        )

        system.textView.deleteForward(nil)

        #expect(system.text == "a c")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
        #expect(system.selectionSet.primaryIndex == 1)
    }

    @Test func mixedSelectedTextAndBareCaretDeleteTogether() {
        let system = mounted("cat dog")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 7, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == " do")
        #expect(system.selectionSet.ranges == [NSRange(location: 0, length: 0), NSRange(location: 3, length: 0)])
    }

    @Test func boundaryCaretStaysWhileAnotherCaretDeletes() {
        let system = mounted("ab")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "a")
        #expect(system.selectionSet.ranges == [NSRange(location: 0, length: 0), NSRange(location: 1, length: 0)])
    }

    @Test func backspaceTreatsCRLFAsOneComposedSeparator() {
        let system = mounted("a\r\nb\r\n")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 3, length: 0), NSRange(location: 6, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "ab")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0), NSRange(location: 2, length: 0)])
    }

    @Test func overlappingCaretsDeleteOneCRLFPairOnlyOnce() {
        let system = mounted("a\r\nb")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 2, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 1
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "ab")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0)])
    }

    @Test func forwardDeleteTreatsCRLFAsOneSeparator() {
        let system = mounted("a\r\nb\r\n")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteForward(nil)

        #expect(system.text == "ab")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0), NSRange(location: 2, length: 0)])
    }

    @Test func selectedHalfOfCRLFDeletesTheWholeSeparator() {
        let system = mounted("a\r\nb")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 1), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "a")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0)])
    }

    @Test func selectedLFHalfAlsoDeletesTheWholeSeparator() {
        let system = mounted("a\r\nb")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 2, length: 1), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "a")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0)])
    }

    @Test func backspaceDeletesWholeEmojiGraphemes() {
        let original = "A👩‍💻B🙂C" as NSString
        let first = original.range(of: "👩‍💻")
        let second = original.range(of: "🙂")
        let system = mounted(original as String)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [
                NSRange(location: NSMaxRange(first), length: 0),
                NSRange(location: NSMaxRange(second), length: 0),
            ],
            primaryIndex: 0
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "ABC")
        #expect(system.selectionSet.ranges == [NSRange(location: 1, length: 0), NSRange(location: 2, length: 0)])
    }

    @Test func backspaceDeletesCombiningClusterAndCJKCharacter() {
        let system = mounted("e\u{301}Z中")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 2, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 1
        )

        system.textView.deleteBackward(nil)

        #expect(system.text == "Z")
        #expect(system.selectionSet.ranges == [NSRange(location: 0, length: 0), NSRange(location: 1, length: 0)])
        #expect(system.selectionSet.primaryIndex == 1)
    }

    @Test func oneHundredBareCaretsUseTheBoundedTransactionPath() {
        let system = mounted(String(repeating: "x ", count: 100))
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: (0 ..< 100).map { NSRange(location: $0 * 2, length: 0) },
            primaryIndex: 0
        )

        system.textView.deleteForward(nil)

        #expect(system.text == String(repeating: " ", count: 100))
        #expect(system.selectionSet.count == 100)
        #expect(system.selectionSet.ranges.map(\.location) == Array(0 ..< 100))
    }

    @Test func readOnlyTextDeclinesBeforeAnySyntheticDelete() {
        let system = mounted("ab cd")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 0)],
            primaryIndex: 0
        )
        system.textView.isEditable = false

        #expect(!system.applyMultiCursorDelete(.backward))
        #expect(system.text == "ab cd")
    }
}
