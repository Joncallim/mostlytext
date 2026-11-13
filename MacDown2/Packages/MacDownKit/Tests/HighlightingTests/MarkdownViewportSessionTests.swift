import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing

@MainActor
@Suite("Mounted Markdown viewport session", .serialized)
struct MarkdownViewportSessionTests {
    @Test(.timeLimit(.minutes(2)))
    // swiftlint:disable:next function_body_length
    func heldOldParseCannotPublishAfterStructuralEdit() async throws {
        let original = "# Heading\n\nalphatarget beta\n"
            + Array(repeating: "padding paragraph\n", count: 100).joined()
        let model = ViewportSourceBox(original)
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
        system.textView.frame = NSRect(x: 0, y: 0, width: 500, height: 3000)
        scroll.layoutSubtreeIfNeeded()
        let word = (original as NSString).range(of: "alphatarget")
        system.textView.setSelectedRange(NSRange(location: word.location, length: 0))
        system.scrollToVisible(utf16Range: word)
        let storage = try #require(system.textView.textStorage)
        let registry = GrammarRegistry()
        let hold = FirstParseHold()
        let session = MarkdownViewportSession(textSystem: system, registry: registry) { source, registry in
            await hold.pauseFirst()
            return try await Task.detached {
                try MarkdownSectionParser.snapshot(source: source, registry: registry)
            }.value
        }
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer { session.tearDown(); gate.uninstall(from: storage) }
        system.preEditObserver = { [weak session] range, replacement, source in
            session?.prepare(range: range, replacement: replacement, oldSource: source)
        }
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            session.didEdit(range: range, delta: delta, postSource: storage.mutableString)
        }

        session.begin()
        let stale = try #require(session.pendingParseForTesting)
        await hold.untilFirstPaused()
        system.textView.insertText("#", replacementRange: NSRange(location: word.location + 5, length: 0))
        await session.waitForPendingParse()
        try expectCurrentTokens(session, system: system, registry: registry)

        await hold.releaseFirst()
        await stale.value
        try expectCurrentTokens(session, system: system, registry: registry)
    }

    @Test(.timeLimit(.minutes(2)))
    // swiftlint:disable:next function_body_length
    func realEditorWordInsertionAndStructuralFallbackMatchFullParse() async throws {
        let original = "# Heading\n\nalphatarget beta\n\n**bold**\n"
            + Array(repeating: "padding paragraph\n", count: 100).joined()
            + "**tailbold**\n"
        let model = ViewportSourceBox(original)
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
        system.textView.frame = NSRect(x: 0, y: 0, width: 500, height: 3000)
        scroll.layoutSubtreeIfNeeded()
        let initialWord = (original as NSString).range(of: "alphatarget")
        system.textView.setSelectedRange(NSRange(location: initialWord.location, length: 0))
        system.scrollToVisible(utf16Range: initialWord)
        let storage = try #require(system.textView.textStorage)
        let registry = GrammarRegistry()
        let session = MarkdownViewportSession(textSystem: system, registry: registry)
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer { session.tearDown(); gate.uninstall(from: storage) }
        system.preEditObserver = { [weak session] range, replacement, source in
            session?.prepare(range: range, replacement: replacement, oldSource: source)
        }
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            session.didEdit(range: range, delta: delta, postSource: storage.mutableString)
        }

        session.begin()
        await session.waitForPendingParse()
        try expectCurrentTokens(session, system: system, registry: registry)

        let word = (model.text as NSString).range(of: "alphatarget")
        let insertion = NSRange(location: word.location + 5, length: 0)
        system.textView.insertText("X", replacementRange: insertion)
        await session.waitForPendingParse()
        #expect(model.text.contains("alphaXtarget"))
        try expectCurrentTokens(session, system: system, registry: registry)

        let structural = (model.text as NSString).range(of: "alphaXtarget")
        system.textView.insertText("#", replacementRange: NSRange(location: structural.location + 5, length: 0))
        await session.waitForPendingParse()
        #expect(model.text.contains("alpha#Xtarget"))
        try expectCurrentTokens(session, system: system, registry: registry)

        let final = (model.text as NSString).length - 1
        system.textView.setSelectedRange(NSRange(location: final, length: 0))
        system.scrollToVisible(utf16Range: NSRange(location: final, length: 1))
        try expectCurrentTokens(session, system: system, registry: registry)
    }

    private func expectCurrentTokens(_ session: MarkdownViewportSession,
                                     system: EditorTextSystem, registry: GrammarRegistry) throws {
        let visible = try #require(system.visibleUTF16Range)
        let source = system.textView.string
        let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        let oracle = try MarkdownSectionCache(source: source, snapshot: snapshot)
        let expected = try oracle.tokens(in: visible)
        #expect(!expected.isEmpty)
        #expect(session.visibleTokens() == expected)
    }
}

private actor FirstParseHold {
    private var hasPaused = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pauseFirst() async {
        guard !hasPaused else { return }
        hasPaused = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func untilFirstPaused() async {
        guard !hasPaused else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func releaseFirst() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class ViewportSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
