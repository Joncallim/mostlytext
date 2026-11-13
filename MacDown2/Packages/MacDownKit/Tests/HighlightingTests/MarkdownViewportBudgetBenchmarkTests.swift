import AppKit
@testable import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing

/// Opt-in Release probe of the mounted session and painter. This is not the
/// shipped app path while viewport colour remains behind the reduced fallback.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_VIEWPORT_BUDGET_BENCH"] == "1"))
struct MarkdownViewportBudgetBenchmarkTests {
    @Test(.timeLimit(.minutes(5)))
    // swiftlint:disable:next function_body_length
    func oneMiBMountedWordEdits() async throws {
        let original = "# Heading\n\nalphatarget beta\n\n"
            + HighlightBudgetFixture.ordinary.markdown(utf8Bytes: 1024 * 1024)
        let model = ViewportBudgetSourceBox(original)
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
        let source = original as NSString
        let first = source.range(of: "alphatarget")
        try #require(first.location != NSNotFound)
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
        var preEditCount = 0
        defer {
            session.tearDown()
            painter.tearDown()
            gate.uninstall(from: storage)
            system.preEditObserver = nil
        }
        session.onPublication = { [weak painter] in painter?.scheduleRefresh() }
        system.preEditObserver = { [weak session] range, replacement, oldSource in
            preEditCount += 1
            session?.prepare(range: range, replacement: replacement, oldSource: oldSource)
        }
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            session.didEdit(range: range, delta: delta, postSource: storage.mutableString)
            painter.didEdit(newRange: range, delta: delta)
        }

        let openStart = DispatchTime.now().uptimeNanoseconds
        session.begin()
        painter.begin()
        await session.waitForPendingParse()
        painter.paintVisible()
        let openMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - openStart) / 1e6
        #expect(!session.visibleTokens().isEmpty)

        var calls: [Double] = []
        var settlements: [Double] = []
        for index in 0 ..< 12 {
            let edit = NSRange(location: first.location + 5, length: index.isMultiple(of: 2) ? 0 : 1)
            let start = DispatchTime.now().uptimeNanoseconds
            system.textView.insertText(index.isMultiple(of: 2) ? "X" : "", replacementRange: edit)
            let afterCall = DispatchTime.now().uptimeNanoseconds
            await session.waitForPendingParse()
            painter.paintVisible()
            let settled = DispatchTime.now().uptimeNanoseconds
            calls.append(Double(afterCall - start) / 1e6)
            settlements.append(Double(settled - start) / 1e6)
        }
        #expect(model.text == original, "alternating edits restored the original source")
        print("VIEWPORT-BUDGET utf8=\(original.utf8.count) open=\(openMilliseconds) ms "
            + "calls=\(calls.map { Int($0) }) ms settled=\(settlements.map { Int($0) }) ms "
            + "visible=\(String(describing: system.visibleUTF16Range)) preEdit=\(preEditCount) "
            + "selected=\(session.selectedWindowCount) matched=\(session.matchedWindowCount) "
            + "local=\(session.localParseCount) full=\(session.fullParseCount)")
    }
}

@MainActor
private final class ViewportBudgetSourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
