import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing
import Themes

/// Opt-in Release measurement of automatic mounted paint after scroll and
/// TextKit undo/redo actions. This uses an ordered AppKit bitmap readback;
/// direct marked-text calls in the separate oracle test are not a real IME
/// timing receipt and are intentionally absent here.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_LIFECYCLE_DISPLAY"] == "1"))
struct ViewportMountedLifecycleDisplayTests {
    @Test(.timeLimit(.minutes(8)))
    // swiftlint:disable:next function_body_length
    func movementAndUndoRedoReachCurrentOraclePaint() async throws {
        let line = String(repeating: "plain words ", count: 15) + "\n"
        let original = "# Top **alpha**\r\n\r\n" + String(repeating: line, count: 5800)
            + "\n## Tail `omega` and café 😊\n"
        try #require(original.utf8.count >= 1 << 20)
        try #require((original as NSString).length < NeonSyntaxHighlighter.viewportMaxUTF16Units)
        let registry = GrammarRegistry()
        let originalOracle = try MarkdownSectionCache(
            source: original, snapshot: MarkdownSectionParser.snapshot(source: original, registry: registry)
        )
        let tailWord = (original as NSString).range(of: "omega")
        try #require(tailWord.location != NSNotFound)
        let edit = NSRange(location: tailWord.location + 2, length: 0)
        let edited = (original as NSString).replacingCharacters(in: edit, with: "X")
        let editedOracle = try MarkdownSectionCache(
            source: edited, snapshot: MarkdownSectionParser.snapshot(source: edited, registry: registry)
        )

        let box = LifecycleDisplaySourceBox(original)
        let identity = UUID().uuidString
        let editorStore = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            identity: identity, configuration: .default, store: editorStore
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close(); editorStore.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(editorStore.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 800, height: 50000)
        scroll.layoutSubtreeIfNeeded()
        try #require(window.isVisible && system.textView.window === window)
        try #require(window.makeFirstResponder(system.textView))
        system.textView.insertionPointColor = .clear
        let syntaxStore = SyntaxHighlightStore()
        let highlighter = try #require(syntaxStore.highlighter(
            for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
        ) as? NeonSyntaxHighlighter)
        defer { syntaxStore.evictAll() }
        try #require(highlighter.state.isVisibleOnly)
        let session = try #require(highlighter.viewportSession)
        let painter = try #require(highlighter.viewportPainter)
        await session.waitForPendingParse()
        try #require(!session.visibleTokens().isEmpty)

        var cases: [[String: Any]] = []
        // swiftlint:disable:next function_body_length
        func measure(_ name: String, source: String, anchor: String,
                     oracle: MarkdownSectionCache, mustMove: Bool = false,
                     action: @MainActor () -> Void) async throws {
            let nsSource = source as NSString
            let anchorRange = nsSource.range(of: anchor)
            try #require(anchorRange.location != NSNotFound, "Missing lifecycle anchor: \(name)")
            let priorVisible = system.visibleUTF16Range
            let priorValidation = painter.validationPassCount
            let requestedAt = DispatchTime.now().uptimeNanoseconds
            action()
            let returnedAt = DispatchTime.now().uptimeNanoseconds
            await session.waitForPendingParse()
            let deadline = requestedAt + 5_000_000_000
            var paintedAt = requestedAt
            var matchedVisible: NSRange?
            while DispatchTime.now().uptimeNanoseconds < deadline {
                await Task.yield()
                guard let visible = system.visibleUTF16Range,
                      NSIntersectionRange(visible, anchorRange).length > 0,
                      !mustMove || visible != priorVisible,
                      painter.validationPassCount > priorValidation,
                      ViewportDisplayBudgetBenchmarkTests.lifecyclePaintMatches(
                          textView: system.textView, visible: visible, oracle: oracle
                      )
                else { continue }
                paintedAt = DispatchTime.now().uptimeNanoseconds
                matchedVisible = visible
                break
            }
            let visible = try #require(matchedVisible, "Automatic current paint did not appear: \(name)")
            let lineRange = nsSource.lineRange(for: anchorRange)
            let capture = NSRange(location: lineRange.location, length: min(80, lineRange.length))
            let readbackAt = try ViewportDisplayBudgetBenchmarkTests.lifecycleReadback(
                host: host, textView: system.textView,
                visible: visible, oracle: oracle, range: capture
            )
            try #require(system.textView.string.utf16.elementsEqual(source.utf16),
                         "Editor source changed during \(name)")
            try #require(box.text.utf16.elementsEqual(source.utf16),
                         "Model source changed during \(name)")
            let expectedTokens = try oracle.tokens(in: visible)
            try #require(session.visibleTokens() == expectedTokens,
                         "Session captures differ after \(name)")
            let milliseconds = { (start: UInt64, end: UInt64) in Double(end - start) / 1_000_000 }
            let total = milliseconds(requestedAt, readbackAt)
            cases.append([
                "case": name,
                "source_utf8_bytes": source.utf8.count,
                "source_utf16_units": nsSource.length,
                "request_to_action_return_ms": milliseconds(requestedAt, returnedAt),
                "request_to_oracle_paint_ms": milliseconds(requestedAt, paintedAt),
                "request_to_bitmap_readback_ms": total,
                "under_50_ms": total < 50,
                "visible_location": visible.location,
                "visible_length": visible.length,
            ])
            let data = try JSONSerialization.data(withJSONObject: cases[cases.count - 1], options: [.sortedKeys])
            try print("VIEWPORT-LIFECYCLE-DISPLAY-CASE " + #require(String(data: data, encoding: .utf8)))
        }

        let topSelection = NSRange(location: (original as NSString).range(of: "alpha").location, length: 0)
        system.selectedRange = topSelection
        try await measure("move-tail", source: original, anchor: "## Tail `omega`", oracle: originalOracle,
                          mustMove: true) {
            system.scrollToVisible(utf16Range: (original as NSString).range(of: "## Tail `omega`"))
        }
        #expect(system.selectedRange == topSelection)
        try await measure("move-top", source: original, anchor: "# Top **alpha**", oracle: originalOracle,
                          mustMove: true) {
            system.scrollToVisible(utf16Range: (original as NSString).range(of: "# Top **alpha**"))
        }
        #expect(system.selectedRange == topSelection)

        // Prepare an actual TextKit undo item outside the timed undo/redo.
        system.scrollToVisible(utf16Range: (original as NSString).range(of: "## Tail `omega`"))
        system.selectedRange = edit
        system.textView.insertText("X", replacementRange: edit)
        system.textView.breakUndoCoalescing()
        await session.waitForPendingParse()
        try #require(system.undoManager.canUndo)
        try await measure("undo", source: original, anchor: "## Tail `omega`", oracle: originalOracle) {
            system.undoManager.undo()
        }
        try #require(system.undoManager.canRedo)
        try await measure("redo", source: edited, anchor: "## Tail `omXega`", oracle: editedOracle) {
            system.undoManager.redo()
        }

        let data = try JSONSerialization.data(withJSONObject: cases, options: [.sortedKeys])
        try print("VIEWPORT-LIFECYCLE-DISPLAY " + #require(String(data: data, encoding: .utf8)))
        #expect(cases.count == 4)
    }
}

@MainActor
private final class LifecycleDisplaySourceBox {
    var text: String
    init(_ text: String) {
        self.text = text
    }
}
