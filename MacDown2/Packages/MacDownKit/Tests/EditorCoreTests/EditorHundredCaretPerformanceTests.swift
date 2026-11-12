import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Measures the E22 100-caret edit budget on a real mounted TextKit 2 editor.
/// Highlighter debounce is outside this package target and outside the timing.
@MainActor
@Suite("Editor 100-caret Release budget")
struct EditorHundredCaretPerformanceTests {
    @Test func splicedUTF16GapsKeepEmojiCombiningMarksAndCRLF() {
        let row = "🧭e\u{301}\r\n"
        let original = String(repeating: row, count: 128)
        let rowLength = (row as NSString).length
        let system = EditingAssistIntegrationSupport.makeSystem(text: original)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: (0 ..< 128).map { NSRange(location: $0 * rowLength, length: 0) },
            primaryIndex: 73
        )

        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == String(repeating: "X" + row, count: 128))
        #expect(system.selectionSet.count == 128)
        #expect(system.selectionSet.primaryIndex == 73)
        system.undoManager.undo()
        #expect(system.text == original)
    }

    @Test func insertionAcrossOneMegabyteKeepsEveryCaretAndOneUndo() {
        let original = String(repeating: "abcd\n", count: 200_000)
        #expect(original.utf8.count == 1_000_000)
        let system = EditingAssistIntegrationSupport.makeSystem(text: original)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        let carets = (0 ..< 100).map { NSRange(location: $0 * 10000 + 2, length: 0) }
        system.selectionSet = EditorSelectionSet(ranges: carets, primaryIndex: 57)
        #expect(system.selectionSet.ranges == carets)

        let elapsed = ContinuousClock().measure {
            system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        let elapsedMilliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        print("100-caret 1-MB mounted insert: \(elapsedMilliseconds) ms")
        #expect(system.text.utf8.count == 1_000_100)
        #expect(system.text.filter { $0 == "X" }.count == 100)
        #expect(system.selectionSet.count == 100)
        #expect(system.selectionSet.primaryIndex == 57)
        #expect(system.selectionSet.ranges == carets.enumerated().map { index, range in
            NSRange(location: range.location + index + 1, length: 0)
        })
        #expect(system.undoManager.canUndo)
        system.undoManager.undo()
        #expect(system.text == original)
        #expect(system.undoManager.canRedo)
        system.undoManager.redo()
        #expect(system.text.filter { $0 == "X" }.count == 100)
        #if !DEBUG
            #expect(elapsedMilliseconds < 50,
                    "100-caret mounted insertion took \(elapsedMilliseconds) ms; Release budget is 50 ms")
        #endif
    }
}
