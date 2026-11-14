import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing

@MainActor
@Suite("Mounted Markdown viewport painter", .serialized)
struct MarkdownViewportPainterTests {
    @Test(.timeLimit(.minutes(2)))
    // swiftlint:disable:next function_body_length
    func editBeforePaintedViewportClearsShiftedOffscreenAttributes() async throws {
        let original = "# Heading\n\n**bold** paragraph\n\n"
            + String(repeating: "padding paragraph\n", count: 120)
            + "**tailbold**\n"
        let model = PainterSourceBox(original)
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
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close(); store.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(store.existingSystem(for: identity))
        let scroll = try #require(system.textView.enclosingScrollView)
        scroll.frame = host.bounds
        system.textView.frame = NSRect(x: 0, y: 0, width: 500, height: 5000)
        scroll.layoutSubtreeIfNeeded()
        let storage = try #require(system.textView.textStorage)
        let session = MarkdownViewportSession(textSystem: system, registry: GrammarRegistry())
        let painter = MarkdownViewportPainter(textSystem: system, session: session) { _ in
            [.foregroundColor: NSColor.systemRed]
        }
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer {
            session.tearDown()
            painter.tearDown()
            gate.uninstall(from: storage)
            system.preEditObserver = nil
        }
        session.onPublication = { [weak painter] in painter?.scheduleRefresh() }
        system.preEditObserver = { [weak session] range, replacement, source in
            session?.prepare(range: range, replacement: replacement, oldSource: source)
        }
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            session.didEdit(range: range, delta: delta, postSource: storage.mutableString)
            painter.didEdit(newRange: range, delta: delta)
        }
        let bold = (original as NSString).range(of: "**bold**")
        system.scrollToVisible(utf16Range: bold)
        session.begin()
        painter.begin()
        await session.waitForPendingParse()
        try #require(!session.visibleTokens().isEmpty)
        painter.paintVisible()
        try #require(hasRedRenderingAttributes(system.textView, in: bold))

        // The synchronous storage callback schedules the next paint; it must
        // still remember where TextKit moved the old rendering attributes.
        let prefix = String(repeating: "x", count: 800)
        let insertion = NSRange(location: 3, length: 0)
        system.textView.insertText(prefix, replacementRange: insertion)
        let shiftedBold = NSRange(location: bold.location + (prefix as NSString).length, length: bold.length)
        try #require(hasRedRenderingAttributes(system.textView, in: shiftedBold),
                     "Control: TextKit must retain the shifted old paint until cleanup")
        let tail = (system.textView.string as NSString).range(of: "**tailbold**")
        system.scrollToVisible(utf16Range: tail)
        painter.paintVisible()
        #expect(!hasRedRenderingAttributes(system.textView, in: shiftedBold),
                "A shifted prior viewport must not retain stale syntax paint offscreen")
        await session.waitForPendingParse()
        let returnedVisible = try #require(system.visibleUTF16Range)
        try #require(NSIntersectionRange(returnedVisible, tail).length > 0,
                     "Control: the new viewport must expose the tail bold span")
        try #require(!session.visibleTokens().isEmpty,
                     "Control: current parse must own the new viewport")
        painter.paintVisible()
        #expect(hasRedRenderingAttributes(system.textView, in: tail),
                "The current viewport must receive its current syntax paint")
        let expected = (original as NSString).replacingCharacters(in: insertion, with: prefix)
        #expect(Array(system.textView.string.utf16) == Array(expected.utf16))
        #expect(Array(model.text.utf16) == Array(expected.utf16))
    }

    @Test func rememberedPaintRangeTracksInsertAndDeleteGeometry() {
        let painted = NSRange(location: 100, length: 20)
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 50, oldLength: 0, newLength: 30, postLength: 230
        ) == NSRange(location: 130, length: 20))
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 110, oldLength: 0, newLength: 30, postLength: 230
        ) == NSRange(location: 100, length: 50))
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 50, oldLength: 30, newLength: 0, postLength: 170
        ) == NSRange(location: 70, length: 20))
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 90, oldLength: 20, newLength: 0, postLength: 180
        ) == NSRange(location: 90, length: 10))
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 105, oldLength: 10, newLength: 2, postLength: 192
        ) == NSRange(location: 100, length: 12))
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 100, oldLength: 20, newLength: 0, postLength: 180
        ) == NSRange(location: 100, length: 0))
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: 50, oldLength: 0, newLength: 30, postLength: 135
        ) == nil)
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            painted, editedAt: Int.max, oldLength: 1, newLength: 0, postLength: 180
        ) == nil)
        #expect(MarkdownViewportPainter.rangeAfterEdit(
            NSRange(location: Int.max, length: 20), editedAt: 50,
            oldLength: 0, newLength: 30, postLength: 230
        ) == nil)
    }

    @Test(.timeLimit(.minutes(2)))
    // swiftlint:disable:next function_body_length
    func paintsCurrentViewportAfterEditAndScrollWithoutChangingSource() async throws {
        let original = "# Heading\n\n**bold** paragraph\n"
            + Array(repeating: "padding paragraph\n", count: 100).joined()
            + "**tailbold**\n"
        let model = PainterSourceBox(original)
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
        let first = (original as NSString).range(of: "**bold**")
        system.textView.setSelectedRange(NSRange(location: first.location, length: 0))
        system.scrollToVisible(utf16Range: first)
        let storage = try #require(system.textView.textStorage)
        let registry = GrammarRegistry()
        let session = MarkdownViewportSession(textSystem: system, registry: registry)
        let painter = MarkdownViewportPainter(textSystem: system, session: session) { _ in
            [.foregroundColor: NSColor.systemRed]
        }
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer {
            session.tearDown()
            painter.tearDown()
            gate.uninstall(from: storage)
            system.preEditObserver = nil
        }
        session.onPublication = { [weak painter] in painter?.scheduleRefresh() }
        system.preEditObserver = { [weak session] range, replacement, source in
            session?.prepare(range: range, replacement: replacement, oldSource: source)
        }
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            session.didEdit(range: range, delta: delta, postSource: storage.mutableString)
            painter.didEdit(newRange: range, delta: delta)
        }

        session.begin()
        painter.begin()
        await session.waitForPendingParse()
        try expectPaintMatchesCurrentParse(system: system, registry: registry, painter: painter)
        let firstVisible = try #require(system.visibleUTF16Range)

        let insertion = (model.text as NSString).range(of: "bold")
        system.textView.insertText("X", replacementRange: NSRange(location: insertion.location + 2, length: 0))
        await session.waitForPendingParse()
        #expect(model.text.contains("**boXld**"))
        try expectPaintMatchesCurrentParse(system: system, registry: registry, painter: painter)

        let tail = (model.text as NSString).range(of: "tailbold")
        system.textView.setSelectedRange(NSRange(location: tail.location, length: 0))
        system.scrollToVisible(utf16Range: tail)
        try expectPaintMatchesCurrentParse(system: system, registry: registry, painter: painter)
        #expect(try NSIntersectionRange(firstVisible, #require(system.visibleUTF16Range)).length == 0)
        #expect(!hasRedRenderingAttributes(system.textView, in: firstVisible))
        #expect(system.textView.string == model.text)

        let tailVisible = try #require(system.visibleUTF16Range)
        system.textView.setSelectedRange(NSRange(location: first.location, length: 0))
        system.scrollToVisible(utf16Range: first)
        try expectPaintMatchesCurrentParse(system: system, registry: registry, painter: painter)
        #expect(try NSIntersectionRange(tailVisible, #require(system.visibleUTF16Range)).length == 0)
        #expect(!hasRedRenderingAttributes(system.textView, in: tailVisible))

        // A temporary loss of mounted geometry must not leave the old
        // viewport's rendering colour attached to the document.
        let lastVisible = try #require(system.visibleUTF16Range)
        scroll.documentView = nil
        #expect(system.visibleUTF16Range == nil)
        painter.paintVisible()
        #expect(!hasRedRenderingAttributes(system.textView, in: lastVisible))
    }

    private func expectPaintMatchesCurrentParse(system: EditorTextSystem, registry: GrammarRegistry,
                                                painter: MarkdownViewportPainter) throws {
        let visible = try #require(system.visibleUTF16Range)
        let source = system.textView.string
        let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: registry)
        let oracle = try MarkdownSectionCache(source: source, snapshot: snapshot)
        let tokens = try oracle.tokens(in: visible)
        #expect(!tokens.isEmpty)
        painter.paintVisible()

        let layout = try #require(system.textView.textLayoutManager)
        let content = try #require(layout.textContentManager)
        let origin = content.documentRange.location
        var painted = IndexSet()
        layout.enumerateRenderingAttributes(from: origin, reverse: false) { _, attributes, range in
            let location = content.offset(from: origin, to: range.location)
            let length = content.offset(from: range.location, to: range.endLocation)
            let clipped = NSIntersectionRange(NSRange(location: location, length: length), visible)
            if clipped.length > 0,
               let color = attributes[.foregroundColor] as? NSColor,
               color.isEqual(NSColor.systemRed) {
                painted.insert(integersIn: clipped.location ..< NSMaxRange(clipped))
            }
            return true
        }
        var expected = IndexSet()
        for token in tokens {
            let clipped = NSIntersectionRange(token.range, visible)
            if clipped.length > 0 {
                expected.insert(integersIn: clipped.location ..< NSMaxRange(clipped))
            }
        }
        #expect(painted == expected, "Mounted viewport paint differs from a fresh full parse")
    }

    private func hasRedRenderingAttributes(_ textView: NSTextView, in visible: NSRange) -> Bool {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager
        else { return false }
        var found = false
        layout
            .enumerateRenderingAttributes(from: content.documentRange.location,
                                          reverse: false) { _, attributes, range in
                let location = content.offset(from: content.documentRange.location, to: range.location)
                let length = content.offset(from: range.location, to: range.endLocation)
                if NSIntersectionRange(NSRange(location: location, length: length), visible).length > 0,
                   let color = attributes[.foregroundColor] as? NSColor,
                   color.isEqual(NSColor.systemRed) {
                    found = true
                }
                return !found
            }
        return found
    }
}

@MainActor
private final class PainterSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
