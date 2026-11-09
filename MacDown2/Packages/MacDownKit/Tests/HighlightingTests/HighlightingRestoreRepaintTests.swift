import AppKit
@testable import Highlighting
import Testing

/// Found by a native Pinyin session on the Debug app: after a document left reduced mode (the note disappeared) it
/// stayed
/// visually uncoloured until the next edit, although TextKit held the rendering attributes (logged: four coloured runs,
/// 12
/// styled tokens, yet plain text on screen). The harness has no display, so these tests pin the mechanism that fixes
/// it:
/// a repaint is requested after the restore's styling pass, and that repaint changes nothing but the redraw.
@MainActor
@Suite(.serialized)
struct HighlightingRestoreRepaintTests {
    private typealias Fixtures = SizeFallbackFixtures
    private let cutoff = SizeFallbackFixtures.policy.reduceAboveUTF16Units
    private let small = "# Hi\n\nsome *emphasis* and `code` and **bold**\n"

    private func hosted(_ editor: HighlightedEditor) -> NSWindow {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = editor.textView
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func reducedEditor() async -> HighlightedEditor {
        let editor = Fixtures.editor(units: cutoff - 100)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        editor.insert(Fixtures.markdown(units: 2000), at: 50) // crosses: reduced, plain
        await editor.settle(.seconds(1))
        #expect(editor.mode == .reducedForTestPolicy)
        return editor
    }

    @Test func aRestoreColoursTheDocumentAndRequestsARepaint() async {
        let editor = await reducedEditor()
        let window = hosted(editor)
        defer { window.orderOut(nil) }
        #expect(editor.highlighter.repaintCount == 0)

        editor.textView.insertText(small, replacementRange: NSRange(location: 0, length: editor.length))
        // Idle delay (200 ms in the test policy), then styling and one repaint.
        #expect(await editor.waitUntil { editor.mode == .full && editor.highlighter.repaintCount >= 1 })

        #expect(editor.mode == .full)
        #expect(!editor.isPlain)
        #expect(editor.highlighter.repaintCount >= 1, "no repaint was requested after the restore's styling pass")
    }

    @Test func theRepaintChangesNeitherTheTextNorUndoNorWhatNeonHears() async {
        let editor = await reducedEditor()
        let window = hosted(editor)
        defer { window.orderOut(nil) }
        editor.textView.insertText(small, replacementRange: NSRange(location: 0, length: editor.length))
        editor.textView.breakUndoCoalescing()
        let text = editor.textView.string
        await editor.settle(.milliseconds(400)) // allow the 200 ms idle delay and queued styling to run
        let edits = editor.highlighter.gate.characterEditCount

        #expect(await editor.waitUntil { editor.mode == .full && editor.highlighter.repaintCount >= 1 })
        #expect(editor.mode == .full)
        #expect(editor.highlighter.repaintCount >= 1)
        #expect(editor.textView.string == text)
        #expect(editor.highlighter.gate.characterEditCount == edits, "the repaint is not a character edit")
        // The repaint registered no undo step of its own: one undo takes the text back past the paste.
        editor.system.undoManager.undo()
        #expect(editor.textView.string != text, "one undo must revert the paste, not an attribute edit")
        editor.system.undoManager.redo()
        #expect(editor.textView.string == text)
    }

    @Test func noRepaintIsRequestedOutsideTheRestoreWindow() async {
        let editor = Fixtures.editor(units: 3000)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        editor.insert("typing", at: 10)
        await editor.settle(.seconds(1))
        #expect(editor.highlighter.repaintCount == 0, "ordinary typing must not pay for a repaint")
    }

    @Test func repaintsStopWhenTheWindowEndsAndDoNotTouchAComposition() async {
        let editor = await reducedEditor()
        let window = hosted(editor)
        defer { window.orderOut(nil) }
        editor.textView.insertText(small, replacementRange: NSRange(location: 0, length: editor.length))
        #expect(await editor.waitUntil { editor.mode == .full && editor.highlighter.repaintCount >= 1 })
        await editor.settle(.seconds(2.5)) // let the 2 s repaint window close
        let count = editor.highlighter.repaintCount
        #expect(count >= 1)

        // Window over: further styling passes do not repaint.
        #expect(editor.highlighter.repaintDeadline <= DispatchTime.now().uptimeNanoseconds)
        editor.highlighter.invalidateAll()
        await editor.settle(.seconds(1))
        #expect(editor.highlighter.repaintCount == count)

        // During a composition a repaint is refused.
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(
            location: NSNotFound, length: 0
        ))
        editor.highlighter.repaintRenderingAttributes()
        #expect(editor.highlighter.repaintCount == count, "no storage edit while text is marked")
        editor.textView.unmarkText()

        // A discard clears the window.
        editor.highlighter.repaintDeadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        editor.highlighter.setLanguage(nil)
        #expect(editor.highlighter.repaintDeadline == 0)
    }
}
