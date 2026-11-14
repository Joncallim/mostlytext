import AppKit
@testable import EditorCore
@testable import Highlighting
import SwiftUI
import Testing
import Themes

/// The input-return budget is only one stage of the separate input-to-visible-
/// display gate. This test also proves that releasing a superseded cache does
/// not let stale ranges through while a structural replacement is parsing.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_CACHE_RETIREMENT_BENCH"] == "1"))
struct ViewportCacheRetirementBudgetTests {
    @Test(.timeLimit(.minutes(4)))
    // swiftlint:disable:next function_body_length
    func mountedOneMiBStructuralInputReturnsWithoutDestroyingOldTree() async throws {
        final class Box { var text: String; init(_ text: String) {
            self.text = text
        } }
        let original = "# alphaStart heading\n\n"
            + HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 1_060_000)
        try #require(original.utf8.count >= 1 << 20)
        let box = Box(original)
        let identity = UUID().uuidString
        let editorStore = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            identity: identity, configuration: .default, store: editorStore
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close(); editorStore.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(editorStore.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 800, height: 50000)
        scroll.layoutSubtreeIfNeeded()
        let syntaxStore = SyntaxHighlightStore()
        let highlighter = try #require(syntaxStore.highlighter(
            for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
        ) as? NeonSyntaxHighlighter)
        defer { syntaxStore.evictAll() }
        try #require(highlighter.state.isVisibleOnly)
        let session = try #require(highlighter.viewportSession)
        await session.waitForPendingParse()
        try #require(!session.visibleTokens().isEmpty)

        // A newline within a heading is structural, so this edit must
        // discard the complete old parse before a new full parse publishes.
        let first = NSRange(location: 5, length: 0)
        let input = DispatchTime.now().uptimeNanoseconds
        system.textView.insertText("\n", replacementRange: first)
        let returned = DispatchTime.now().uptimeNanoseconds
        let inputReturnMilliseconds = Double(returned - input) / 1_000_000
        print("VIEWPORT-CACHE-RETIREMENT input_return_ms=\(inputReturnMilliseconds) "
            + "utf8=\(system.textView.string.utf8.count) full=\(session.fullParseCount)")
        #expect(inputReturnMilliseconds < 50, "1 MiB structural input return took \(inputReturnMilliseconds) ms")
        #expect(session.visibleTokens().isEmpty, "An old parse must not style new source")

        // A second edit while the replacement parse is pending must cancel
        // that parse and publish only the final source. It also exercises
        // teardown after the old cache has been handed to the retire worker.
        system.textView.insertText("#", replacementRange: NSRange(location: 7, length: 0))
        await session.waitForPendingParse()
        let expected = (original as NSString).replacingCharacters(in: first, with: "\n")
        let final = (expected as NSString).replacingCharacters(
            in: NSRange(location: 7, length: 0), with: "#"
        )
        let editorMatches = Array(system.textView.string.utf16) == Array(final.utf16)
        let bindingMatches = Array(box.text.utf16) == Array(final.utf16)
        #expect(editorMatches && bindingMatches)
        let visible = try #require(system.visibleUTF16Range)
        let oracle = try MarkdownSectionCache(
            source: final,
            snapshot: MarkdownSectionParser.snapshot(source: final, registry: GrammarRegistry())
        )
        #expect(try session.visibleTokens() == (oracle.tokens(in: visible)))
        syntaxStore.evictAll()
        #expect(highlighter.viewportSession == nil)
    }
}
