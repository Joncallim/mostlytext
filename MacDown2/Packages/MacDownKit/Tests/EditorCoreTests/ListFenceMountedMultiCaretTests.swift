import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("Mounted list-fence multi-caret safety")
struct ListFenceMountedMultiCaretTests {
    @Test("one caret in list code stays literal while a sibling prose caret receives Markdown pairing")
    func codeAndProseCaretsRemainIndependent() {
        let original = "- ```swift\n  code \n- next item "
        let source = original as NSString
        let code = source.range(of: "code ")
        let prose = source.range(of: "next item ")
        let system = EditingAssistIntegrationSupport.makeMarkdownSystem(text: original)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        system.selectionSet = EditorSelectionSet(
            ranges: [
                NSRange(location: NSMaxRange(code), length: 0),
                NSRange(location: NSMaxRange(prose), length: 0),
            ],
            primaryIndex: 1
        )

        system.textView.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(system.text == "- ```swift\n  code *\n- next item **")
        #expect(system.selectionSet.count == 2)
        #expect(system.selectionSet.primaryIndex == 1)
        system.undoManager.undo()
        #expect(system.text == original)
    }
}
