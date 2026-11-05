import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

/// Review pass 2 (P0s): after the per-tab undo manager change Edit ▸ Undo no longer undid typing,
/// an undo/redo never reached the SwiftUI binding (so Save wrote the pre-undo text), and
/// `setText` left an undo history that crashed with NSRangeException.
@MainActor
struct EditorUndoPublicationTests {
    private final class Box {
        var value: String
        var sets = 0
        init(_ value: String) {
            self.value = value
        }
    }

    private struct Mounted {
        let system: EditorTextSystem
        let box: Box
        let window: NSWindow
    }

    private func mountEditor(text: String) -> Mounted {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let box = Box(text)
        let binding = Binding<String>(get: { box.value }, set: { box.value = $0; box.sets += 1 })
        let hosting = NSHostingView(rootView: EditorView(
            text: binding,
            identity: identity,
            configuration: .default,
            store: store
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none // headless tests: window transition animations leak blocked dispatch workers
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        let system = store.system(for: identity, initialText: text, configuration: .default)
        return Mounted(system: system, box: box, window: window)
    }

    @Test func undoAndRedoReachTheBinding() {
        let mounted = mountEditor(text: "hello")
        defer { mounted.window.orderOut(nil) }
        let system = mounted.system
        system.selectedRange = NSRange(location: 5, length: 0)
        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        system.textView.breakUndoCoalescing()
        #expect(mounted.box.value == "helloX")

        system.undoManager.undo()
        #expect(system.text == "hello")
        #expect(mounted.box.value == "hello", "undo must be published to the model")

        system.undoManager.redo()
        #expect(system.text == "helloX")
        #expect(mounted.box.value == "helloX", "redo must be published to the model")
    }

    @Test func editUndoAndRedoActionsReachTheTabsUndoManagerThroughTheResponderChain() {
        let mounted = mountEditor(text: "hello")
        defer { mounted.window.orderOut(nil) }
        let system = mounted.system
        system.selectedRange = NSRange(location: 5, length: 0)
        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        system.textView.breakUndoCoalescing()
        mounted.window.makeFirstResponder(system.textView)
        let responder = mounted.window.firstResponder

        #expect(responder?.tryToPerform(#selector(EditorTextView.undo(_:)), with: nil) == true)
        #expect(system.text == "hello", "Cmd-Z must undo typing")
        #expect(mounted.box.value == "hello")
        #expect(responder?.tryToPerform(#selector(EditorTextView.redo(_:)), with: nil) == true)
        #expect(system.text == "helloX")
        #expect(mounted.box.value == "helloX")
    }

    @Test func undoMenuItemsValidateAgainstTheTabsOwnHistory() {
        let mounted = mountEditor(text: "hello")
        defer { mounted.window.orderOut(nil) }
        let system = mounted.system
        let item = NSMenuItem(title: "Undo", action: #selector(EditorTextView.undo(_:)), keyEquivalent: "z")
        #expect(system.textView.validateUserInterfaceItem(item) == false)

        system.selectedRange = NSRange(location: 5, length: 0)
        system.textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        system.textView.breakUndoCoalescing()

        #expect(system.textView.validateUserInterfaceItem(item) == true)
    }

    @Test func aWholeDocumentSetTextClearsTheUndoHistoryInsteadOfLeavingItToCrash() {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "hello world long text")
        let window = EditingAssistIntegrationSupport.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.insertText("ZZZZZZZZZZ", replacementRange: NSRange(location: 15, length: 0))
        system.textView.breakUndoCoalescing()

        system.setText("hi")

        #expect(!system.undoManager.canUndo)
        system.undoManager.undo() // a no-op now; used to raise NSRangeException
        #expect(system.text == "hi")
    }
}
