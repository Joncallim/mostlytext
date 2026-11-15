import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing
import Themes

/// Opt-in full-size lifecycle control. This checks mounted editor ownership and
/// authored text; the separate display benchmark owns the timing claim.
@MainActor
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_LIFECYCLE_ORACLE"] == "1")
)
struct ViewportMountedLifecycleOracleTests {
    @Test(.timeLimit(.minutes(8)))
    // swiftlint:disable:next function_body_length
    func movementUndoRedoAndCompositionMatchIndependentVisibleParse() async throws {
        let line = String(repeating: "plain words ", count: 15) + "\n"
        let original =
            "# Top **alpha**\r\n\r\n" + String(repeating: line, count: 5800)
                + "\n## Tail `omega` and café 😊\n"
        try #require(original.utf8.count >= 1 << 20)
        try #require((original as NSString).length < NeonSyntaxHighlighter.viewportMaxUTF16Units)

        let model = LifecycleSourceBox(original)
        let identity = UUID().uuidString
        let editorStore = EditorTextSystemStore()
        let host = NSHostingView(
            rootView: EditorView(
                text: Binding(get: { model.text }, set: { model.text = $0 }),
                identity: identity, configuration: .default, store: editorStore
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
            editorStore.evictAll()
        }
        host.layoutSubtreeIfNeeded()
        let system = try #require(editorStore.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        scroll.layoutSubtreeIfNeeded()
        try #require(window.makeFirstResponder(system.textView))

        let syntaxStore = SyntaxHighlightStore()
        let highlighter = try #require(
            syntaxStore.highlighter(
                for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
            ) as? NeonSyntaxHighlighter
        )
        defer { syntaxStore.evictAll() }
        try #require(highlighter.state.isVisibleOnly)
        let session = try #require(highlighter.viewportSession)
        let painter = try #require(highlighter.viewportPainter)
        await session.waitForPendingParse()
        let registry = GrammarRegistry()

        func verify(_ expectedSource: String, anchor: String) async throws {
            await session.waitForPendingParse()
            try #require(
                system.textView.string.utf16.elementsEqual(expectedSource.utf16),
                "Mounted source differs after \(anchor)"
            )
            try #require(
                model.text.utf16.elementsEqual(expectedSource.utf16),
                "Published model differs after \(anchor)"
            )
            try #require(highlighter.state.isVisibleOnly)
            let anchorRange = (expectedSource as NSString).range(of: anchor)
            try #require(anchorRange.location != NSNotFound)
            system.scrollToVisible(utf16Range: anchorRange)
            scroll.layoutSubtreeIfNeeded()
            painter.paintVisible()
            let visible = try #require(system.visibleUTF16Range)
            try #require(
                NSIntersectionRange(visible, anchorRange).length > 0,
                "The requested anchor is outside the mounted viewport: \(anchor)"
            )
            let snapshot = try MarkdownSectionParser.snapshot(source: expectedSource, registry: registry)
            let oracle = try MarkdownSectionCache(source: expectedSource, snapshot: snapshot)
            let expectedTokens = try oracle.tokens(in: visible)
            try #require(!expectedTokens.isEmpty)
            #expect(session.visibleTokens() == expectedTokens)
            #expect(system.selectedRange.location <= (expectedSource as NSString).length)
            #expect(NSMaxRange(system.selectedRange) <= (expectedSource as NSString).length)
        }

        let topSelection = NSRange(
            location: (original as NSString).range(of: "alpha").location, length: 0
        )
        system.selectedRange = topSelection
        try await verify(original, anchor: "## Tail `omega`")
        #expect(system.selectedRange == topSelection, "Viewport movement must preserve the selection")
        try await verify(original, anchor: "# Top **alpha**")
        #expect(system.selectedRange == topSelection)

        let tailWord = (original as NSString).range(of: "omega")
        let editRange = NSRange(location: tailWord.location + 2, length: 0)
        let edited = (original as NSString).replacingCharacters(in: editRange, with: "X")
        system.selectedRange = editRange
        system.textView.insertText("X", replacementRange: editRange)
        system.textView.breakUndoCoalescing()
        try await verify(edited, anchor: "## Tail `omXega`")
        try #require(system.undoManager.canUndo)
        system.undoManager.undo()
        try await verify(original, anchor: "## Tail `omega`")
        try #require(system.undoManager.canRedo)
        system.undoManager.redo()
        try await verify(edited, anchor: "## Tail `omXega`")

        let insertion = NSRange(location: (edited as NSString).range(of: "café").location, length: 0)
        let composed = (edited as NSString).replacingCharacters(in: insertion, with: "に")
        system.selectedRange = insertion
        system.textView.setMarkedText(
            "に", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        try #require(system.textView.hasMarkedText())
        system.textView.unmarkText()
        #expect(!system.textView.hasMarkedText())
        try await verify(composed, anchor: "にcafé")
        #expect(
            highlighter.viewportSession === session, "Composition must keep one mounted parse owner"
        )
    }
}

@MainActor
private final class LifecycleSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
