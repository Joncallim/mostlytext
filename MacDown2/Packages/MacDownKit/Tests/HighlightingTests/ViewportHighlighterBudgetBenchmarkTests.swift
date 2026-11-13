import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing
import Themes

/// Opt-in Release measurement of the actual highlighter integration path.
/// The app still leaves this owner disabled until the whole workload qualifies.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_BUDGET_BENCH"] == "1"))
struct ViewportHighlighterBudgetBenchmarkTests {
    @Test(.timeLimit(.minutes(5)))
    // swiftlint:disable:next function_body_length
    func oneMiBHighlighterWordEdits() async throws {
        let original = "# Heading\n\nalphatarget beta\n\n"
            + HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 1024 * 1024)
        let model = ViewportHighlighterBudgetSourceBox(original)
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            identity: identity, configuration: .default, store: store
        ))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        window.contentView = host
        defer { window.orderOut(nil); window.close(); store.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(store.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 800, height: 50000)
        scroll.layoutSubtreeIfNeeded()
        let word = (original as NSString).range(of: "alphatarget")
        try #require(word.location != NSNotFound)
        system.textView.setSelectedRange(NSRange(location: word.location, length: 0))
        system.scrollToVisible(utf16Range: word)

        let openStart = DispatchTime.now().uptimeNanoseconds
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: "markdown", theme: BundledThemes.light,
            registry: GrammarRegistry(), enableViewport: true
        )
        defer { highlighter.tearDown() }
        #expect(highlighter.state.isVisibleOnly)
        let session = try #require(highlighter.viewportSession)
        await session.waitForPendingParse()
        highlighter.viewportPainter?.paintVisible()
        let openMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - openStart) / 1e6
        #expect(!session.visibleTokens().isEmpty)

        var calls: [Double] = []
        var settlements: [Double] = []
        for index in 0 ..< 12 {
            let edit = NSRange(location: word.location + 5, length: index.isMultiple(of: 2) ? 0 : 1)
            let start = DispatchTime.now().uptimeNanoseconds
            system.textView.insertText(index.isMultiple(of: 2) ? "X" : "", replacementRange: edit)
            let afterCall = DispatchTime.now().uptimeNanoseconds
            await session.waitForPendingParse()
            highlighter.viewportPainter?.paintVisible()
            let settled = DispatchTime.now().uptimeNanoseconds
            calls.append(Double(afterCall - start) / 1e6)
            settlements.append(Double(settled - start) / 1e6)
        }
        #expect(model.text == original)
        #expect(session.localParseCount == 12)
        #expect(session.fullParseCount == 1)
        print("VIEWPORT-HIGHLIGHTER-BUDGET utf8=\(original.utf8.count) open=\(openMilliseconds) ms "
            + "calls=\(calls.map { Int($0) }) ms settled=\(settlements.map { Int($0) }) ms "
            + "selected=\(session.selectedWindowCount) matched=\(session.matchedWindowCount) "
            + "local=\(session.localParseCount) full=\(session.fullParseCount)")
    }
}

@MainActor
private final class ViewportHighlighterBudgetSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
