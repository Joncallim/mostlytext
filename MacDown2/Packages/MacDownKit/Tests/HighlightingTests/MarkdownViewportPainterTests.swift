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

        let insertion = (model.text as NSString).range(of: "bold")
        system.textView.insertText("X", replacementRange: NSRange(location: insertion.location + 2, length: 0))
        await session.waitForPendingParse()
        #expect(model.text.contains("**boXld**"))
        try expectPaintMatchesCurrentParse(system: system, registry: registry, painter: painter)

        let tail = (model.text as NSString).range(of: "tailbold")
        system.textView.setSelectedRange(NSRange(location: tail.location, length: 0))
        system.scrollToVisible(utf16Range: tail)
        try expectPaintMatchesCurrentParse(system: system, registry: registry, painter: painter)
        #expect(system.textView.string == model.text)
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
}

@MainActor
private final class PainterSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
