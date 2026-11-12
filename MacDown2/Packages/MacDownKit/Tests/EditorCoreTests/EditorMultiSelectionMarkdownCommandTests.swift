import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("EditorTextSystem multi-selection Markdown commands")
struct EditorMultiSelectionMarkdownCommandTests {
    private func mountedMarkdown(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = EditingAssistIntegrationSupport.makeMarkdownSystem(text: text)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        system.textView.delegate = EditingAssistIntegrationSupport.makeCoordinator(system: system)
        return (system, window)
    }

    @Test func boldWrapsBothSelectedWordsInOneUndoStep() {
        let (system, window) = mountedMarkdown("cat dog")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            primaryIndex: 1
        )

        #expect(system.performMarkdownCommand(.bold))

        #expect(system.text == "**cat** **dog**")
        #expect(system.selectionSet.ranges == [NSRange(location: 2, length: 3), NSRange(location: 10, length: 3)])
        #expect(system.selectionSet.primaryIndex == 1)
        system.undoManager.undo()
        #expect(system.text == "cat dog")
    }

    @Test func boldCreatesPairsAtBothBareCarets() {
        let (system, window) = mountedMarkdown("a b")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)],
            primaryIndex: 0
        )

        #expect(system.performMarkdownCommand(.bold))

        #expect(system.text == "a**** b****")
        #expect(system.selectionSet.ranges == [NSRange(location: 3, length: 0), NSRange(location: 9, length: 0)])
    }

    @Test func italicTogglesExistingAndNewSelectionsIndependently() {
        let (system, window) = mountedMarkdown("*cat* dog")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 1, length: 3), NSRange(location: 6, length: 3)],
            primaryIndex: 0
        )

        #expect(system.performMarkdownCommand(.italic))

        #expect(system.text == "cat *dog*")
        #expect(system.selectionSet.ranges == [NSRange(location: 0, length: 3), NSRange(location: 5, length: 3)])
    }

    @Test func headingAppliesToTwoDifferentLines() {
        let (system, window) = mountedMarkdown("a\nb")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)],
            primaryIndex: 0
        )

        #expect(system.performMarkdownCommand(.heading(level: 1)))

        #expect(system.text == "# a\n# b")
        #expect(system.selectionSet.count == 2)
    }

    @Test func headingAppliesOnceWhenTwoCaretsShareOneLine() {
        let (system, window) = mountedMarkdown("abc")
        defer { window.orderOut(nil) }
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)],
            primaryIndex: 1
        )

        #expect(system.performMarkdownCommand(.heading(level: 1)))

        #expect(system.text == "# abc")
        #expect(system.selectionSet.count == 2)
        #expect(system.selectionSet.primaryIndex == 1)
    }

    @Test func overlappingExpandedHeadingRangesDeclineAtomically() {
        let (system, window) = mountedMarkdown("ab\ncd")
        defer { window.orderOut(nil) }
        let originalSelection = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 4), NSRange(location: 5, length: 0)],
            primaryIndex: 1
        )
        system.selectionSet = originalSelection

        #expect(!system.performMarkdownCommand(.heading(level: 1)))

        #expect(system.text == "ab\ncd")
        #expect(system.selectionSet == originalSelection)
        #expect(!system.undoManager.canUndo)
    }

    @Test func explicitMarkdownCommandDeclinesForGeneralText() {
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .general
        let system = EditingAssistIntegrationSupport.makeSystem(text: "cat", configuration: configuration)
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3)

        #expect(!system.performMarkdownCommand(.bold))
        #expect(system.text == "cat")
    }
}
