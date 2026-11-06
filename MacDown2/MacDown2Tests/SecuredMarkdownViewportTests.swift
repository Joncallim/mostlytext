import AppKit
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
import Themes

@MainActor
@Suite("Secured Markdown stable viewport", .serialized)
struct SecuredMarkdownViewportTests {
    private let parserIdentity = UUID()

    @Test func resourceFrameReplacementKeepsTheNativeScrollContainerPositionAndFocus() async throws {
        let source = (0 ..< 29).map { "## ROW-\($0)-END\n\n" }.joined() + "## OLD-29-END\n"
        let newerSource = source.replacingOccurrences(of: "OLD-29-END", with: "NEW-29-END")
        let engine = ParseEngine()
        let firstParse = try await engine.parse(source, revision: 1)
        let secondParse = try await engine.parse(newerSource, revision: 2)
        let document = FileDocument(text: newerSource)
        let tabID = UUID()
        let owner = PreviewResourceWindowState()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let recorder = ViewportResourceRecorder()
        let host = NSHostingView(rootView: view(document, (firstParse, source), tabID, owner, recorder))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = host
        let application = NSApplication.shared
        if !NSRunningApplication.current.isFinishedLaunching {
            application.finishLaunching()
        }
        application.activate()
        window.makeKeyAndOrderFront(nil)
        try await HeadingNativeHarness.requireOwnAccessibilityRole()
        defer {
            owner.close()
            window.orderOut(nil)
            window.close()
        }
        let original = try await readyScroll(in: host, recorder: recorder, after: nil, lastMarker: "OLD-29-END")
        let firstID = try #require(recorder.loadID)
        original.contentView.scroll(to: NSPoint(x: 0, y: 400))
        original.reflectScrolledClipView(original.contentView)
        let offset = original.contentView.bounds.origin.y
        #expect(offset > 150, "The real Preview must be scrolled before replacement")
        let focus = try #require(window.firstResponder)
        host.rootView = view(document, (secondParse, newerSource), tabID, owner, recorder)
        let replacement = try await readyScroll(in: host, recorder: recorder, after: firstID, lastMarker: "NEW-29-END")
        #expect(replacement === original, "Resource replacement must retain the native scroll container")
        #expect(abs(replacement.contentView.bounds.origin.y - offset) < 1)
        #expect(window.firstResponder === focus)
    }

    @ViewBuilder
    private func view(
        _ document: FileCore.FileDocument,
        _ published: (document: MarkdownDocument, text: String),
        _ tabID: UUID,
        _ owner: PreviewResourceWindowState,
        _ recorder: ViewportResourceRecorder
    ) -> some View {
        if let frame = PreviewResourceParsedFrame(parserIdentity: parserIdentity, document: published.document) {
            SecuredMarkdownResourceHost(tabID: tabID, document: document,
                                        sourceGeneration: document.mutationGeneration,
                                        parsedFrame: frame) { loader, id in
                TextualMarkdownPreview(document: published.document, text: published.text,
                                       theme: PreviewTheme(theme: BundledThemes.light), controller: recorder.controller,
                                       resourceImageLoader: loader, resourceLoadID: id)
                    .onChange(of: id, initial: true) { _, value in recorder.loadID = value }
            }
            .environment(\.previewResourceWindowState, owner)
        }
    }

    private func readyScroll(in host: NSView, recorder: ViewportResourceRecorder,
                             after prior: UUID?, lastMarker: String) async throws -> NSScrollView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            host.window?.displayIfNeeded()
            if let id = recorder.loadID, id != prior, let scroll = overflowingScroll(in: host),
               containsAllRows(in: host, lastMarker: lastMarker) {
                return scroll
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let values = accessibleValues(in: host)
        var containers: [String] = []
        func describe(_ view: NSView, depth: Int) {
            guard depth < 30 else { return }
            if let scroll = view as? NSScrollView {
                containers
                    .append(
                        "clip=\(scroll.contentView.bounds) document=\(String(describing: scroll.documentView?.bounds))"
                    )
            }
            view.subviews.forEach { describe($0, depth: depth + 1) }
        }
        describe(host, depth: 0)
        Issue.record("""
        The actual overflowing Preview did not publish its new resource frame and final row.
        prior=\(String(describing: prior)) current=\(String(describing: recorder.loadID)); marker=\(lastMarker)
        Scroll containers: \(containers.joined(separator: "; "))
        Native text: \(values.prefix(80).joined(separator: " | "))
        """)
        throw CocoaError(.coderInvalidValue)
    }

    private func overflowingScroll(in view: NSView) -> NSScrollView? {
        var candidates: [NSScrollView] = []
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, let content = scroll.documentView,
               content.bounds.height > scroll.contentView.bounds.height + 200 {
                candidates.append(scroll)
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func containsAllRows(in host: NSView, lastMarker: String) -> Bool {
        let values = accessibleValues(in: host)
        let markers = (0 ..< 29).map { "ROW-\($0)-END" } + [lastMarker]
        return markers.allSatisfy { marker in values.contains { $0.contains(marker) } }
    }

    private func accessibleValues(in host: NSView) -> [String] {
        var values: [String] = []
        for node in HeadingNativeHarness.nodes(in: host) {
            for name in ["accessibilityLabel", "accessibilityValue"] {
                let selector = NSSelectorFromString(name)
                guard node.responds(to: selector), let value = node.perform(selector)?.takeUnretainedValue() else {
                    continue
                }
                if let value = value as? String {
                    values.append(value)
                }
                if let value = value as? NSAttributedString {
                    values.append(value.string)
                }
            }
        }
        return values
    }
}

@MainActor
private final class ViewportResourceRecorder {
    let controller = ScrollSyncController()
    var loadID: UUID?
}
