import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing
import Themes

@MainActor
@Suite("Mounted viewport highlighter integration", .serialized)
struct ViewportHighlighterIntegrationTests {
    @Test func cachedReducedHighlighterAdmitsViewportAfterEditorMount() async throws {
        let initial = "# Heading\n\n" + String(repeating: "plain words\n", count: 1000)
        let identity = UUID().uuidString
        let system = EditorTextSystem(identity: identity, initialText: initial, configuration: .default)
        let syntaxStore = SyntaxHighlightStore()
        let highlighter = try #require(
            syntaxStore.highlighter(
                for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
            ) as? NeonSyntaxHighlighter
        )
        #expect(highlighter.state.isReduced)
        #expect(!highlighter.state.isVisibleOnly)
        #expect(highlighter.viewportSession == nil)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        scroll.documentView = system.textView
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { syntaxStore.evictAll(); window.orderOut(nil); window.close() }
        let cached = try #require(
            syntaxStore.highlighter(
                for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
            ) as? NeonSyntaxHighlighter
        )
        #expect(cached === highlighter)
        #expect(cached.state.isVisibleOnly)
        #expect(syntaxStore.state(for: identity)?.isVisibleOnly == true)
        #expect(system.preEditObserver != nil)
        let session = try #require(cached.viewportSession)
        await session.waitForPendingParse()
        #expect(session.fullParseCount == 1)
        #expect(system.textView.string == initial)
    }

    @Test(.timeLimit(.minutes(2)))
    func crossingViewportAdmissionReturnsToReducedAndCanRestore() async throws {
        let initial = "# Heading\n\n" + String(repeating: "plain words\n", count: 1000)
        let identity = UUID().uuidString
        let system = EditorTextSystem(identity: identity, initialText: initial, configuration: .default)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        scroll.documentView = system.textView
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        let syntaxStore = SyntaxHighlightStore()
        defer { syntaxStore.evictAll(); window.orderOut(nil); window.close() }
        let highlighter = try #require(
            syntaxStore.highlighter(
                for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
            ) as? NeonSyntaxHighlighter
        )
        #expect(highlighter.state.isVisibleOnly)
        let append = String(repeating: "x", count: NeonSyntaxHighlighter.viewportMaxUTF16Units)
        system.textView.insertText(append, replacementRange: NSRange(location: (initial as NSString).length, length: 0))
        #expect(highlighter.state.isReduced)
        #expect(!highlighter.state.isVisibleOnly)
        #expect(highlighter.viewportSession == nil)
        #expect(system.preEditObserver == nil)
        #expect(system.textView.string == initial + append)

        syntaxStore.evict(identity)
        let reopened = try #require(
            syntaxStore.highlighter(
                for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
            ) as? NeonSyntaxHighlighter
        )
        #expect(reopened.state.isReduced)
        #expect(reopened.viewportSession == nil)
        reopened.restoreSleep = { _ in }
        system.textView.insertText("", replacementRange: NSRange(
            location: (initial as NSString).length, length: append.utf16.count
        ))
        await reopened.restoreTask?.value
        #expect(reopened.state.isVisibleOnly)
        #expect(reopened.viewportSession != nil)
        #expect(system.textView.string == initial)
    }

    @Test func closeDuringDeferredThresholdTransitionCannotResurrectOwner() async throws {
        let initial = "# Heading\n\n" + String(repeating: "plain words\n", count: 400)
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: initial, configuration: .default)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        scroll.documentView = system.textView
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.orderOut(nil); window.close() }
        let storage = try #require(system.textView.textStorage)
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: "markdown", theme: BundledThemes.light,
            registry: GrammarRegistry(), enableViewport: true
        )
        #expect(highlighter.state.mode == .full)
        system.textView.insertText(String(repeating: "more words\n", count: 500),
                                   replacementRange: NSRange(location: 20, length: 0))
        #expect(highlighter.state.isReduced)
        highlighter.tearDown()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(highlighter.isTornDown)
        #expect(highlighter.viewportSession == nil)
        #expect(system.preEditObserver == nil)
        #expect(storage.delegate == nil)
    }

    @Test(.timeLimit(.minutes(2)))
    // swiftlint:disable:next function_body_length
    func largeMarkdownEditsThemeAndLanguageSwitchKeepOneOwner() async throws {
        let original = "# Heading\n\nalphatarget beta\n\n"
            + Array(repeating: "## Section\n\npadding paragraph\n\n", count: 500).joined()
        let model = ViewportIntegrationSourceBox(original)
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            identity: identity, configuration: .default, store: store
        ))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 250),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 250)
        window.contentView = host
        defer { window.orderOut(nil); window.close(); store.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(store.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 500, height: 20000)
        scroll.layoutSubtreeIfNeeded()
        let word = (original as NSString).range(of: "alphatarget")
        system.textView.setSelectedRange(NSRange(location: word.location, length: 0))
        system.scrollToVisible(utf16Range: word)

        let syntaxStore = SyntaxHighlightStore()
        let highlighter = try #require(
            syntaxStore.highlighter(
                for: identity, textSystem: system, languageID: "markdown", theme: BundledThemes.light
            ) as? NeonSyntaxHighlighter
        )
        defer { syntaxStore.evictAll() }
        #expect(highlighter.state.isVisibleOnly)
        #expect(syntaxStore.state(for: identity)?.isVisibleOnly == true)
        #expect(highlighter.highlighter == nil)
        let session = try #require(highlighter.viewportSession)
        await session.waitForPendingParse()
        highlighter.viewportPainter?.paintVisible()
        #expect(hasRenderedColour(system.textView))

        system.textView.insertText("X", replacementRange: NSRange(location: word.location + 5, length: 0))
        await session.waitForPendingParse()
        #expect(session.localParseCount == 1)
        #expect(model.text.contains("alphaXtarget"))
        #expect(highlighter.state.isVisibleOnly)
        let beforeStructuralEdit = session.fullParseCount
        system.textView.insertText("\n", replacementRange: NSRange(location: word.location + 6, length: 0))
        await session.waitForPendingParse()
        #expect(session.fullParseCount == beforeStructuralEdit + 1)
        #expect(model.text.contains("alphaX\ntarget"))
        #expect(highlighter.state.isVisibleOnly)
        highlighter.applyTheme(BundledThemes.dark)
        highlighter.viewportPainter?.paintVisible()
        #expect(hasRenderedColour(system.textView))
        highlighter.applyFont(NSFont.monospacedSystemFont(ofSize: 17, weight: .regular))
        highlighter.viewportPainter?.paintVisible()
        #expect(hasRenderedColour(system.textView))
        let fullParses = session.fullParseCount
        highlighter.invalidateAll()
        await session.waitForPendingParse()
        #expect(session.fullParseCount == fullParses + 1)
        highlighter.viewportPainter?.paintVisible()
        #expect(hasRenderedColour(system.textView))

        highlighter.setLanguage(nil)
        #expect(highlighter.state.mode == .plain)
        #expect(highlighter.viewportSession == nil)
        #expect(system.preEditObserver == nil)
        #expect(session.visibleTokens().isEmpty)
        #expect(!hasRenderedColour(system.textView))

        highlighter.setLanguage("markdown")
        #expect(highlighter.state.isVisibleOnly)
        #expect(highlighter.viewportSession !== session)
        syntaxStore.evict(identity)
        #expect(highlighter.viewportSession == nil)
        #expect(system.preEditObserver == nil)
        #expect(syntaxStore.state(for: identity) == nil)
        #expect(system.textView.string == model.text)
    }

    private func hasRenderedColour(_ textView: NSTextView) -> Bool {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager
        else { return false }
        let origin = content.documentRange.location
        var found = false
        layout.enumerateRenderingAttributes(from: origin, reverse: false) { _, attributes, _ in
            found = attributes[.foregroundColor] is NSColor
            return !found
        }
        return found
    }
}

@MainActor
private final class ViewportIntegrationSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
