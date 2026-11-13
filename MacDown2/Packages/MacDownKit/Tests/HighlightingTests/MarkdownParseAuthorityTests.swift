import AppKit
import EditorCore
import Foundation
@testable import Highlighting
import SwiftUI
import Testing

@MainActor
struct MarkdownParseAuthorityTests {
    @Test func mountedStorageGateInvalidatesParseBeforeModelRevision() throws {
        let initial = "alpha 😀\r\nbeta"
        let model = AuthoritySourceBox(initial)
        let identity = UUID().uuidString
        let store = EditorTextSystemStore()
        let host = NSHostingView(rootView: EditorView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            identity: identity, configuration: .default, store: store
        ))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 250),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil); window.close(); store.evictAll() }
        host.layoutSubtreeIfNeeded()
        let system = try #require(store.existingSystem(for: identity))
        let storage = try #require(system.textView.textStorage)
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer { gate.uninstall(from: storage) }

        let owner = MarkdownParseAuthority()
        let pending = try #require(owner.ticket())
        let priorRevision = system.contentRevision
        var sawOldModelAtGate = false
        var sawOldRevisionAtGate = false
        var refusedPendingAtGate = false
        gate.didProcessCharacterEditWithGeometry = { _, _, _ in
            owner.noteStorageEdit()
            sawOldModelAtGate = model.text == initial
            sawOldRevisionAtGate = system.contentRevision == priorRevision
            refusedPendingAtGate = !owner.admits(pending)
        }
        let target = (initial as NSString).range(of: "beta")
        system.textView.insertText("gamma", replacementRange: target)

        #expect(sawOldModelAtGate)
        #expect(sawOldRevisionAtGate)
        #expect(refusedPendingAtGate)
        #expect(!owner.admits(pending))
        #expect(model.text == "alpha 😀\r\ngamma")
        #expect(system.contentRevision > priorRevision)
        let current = try #require(owner.ticket())
        #expect(owner.admits(current))
    }

    @Test func themeChangeAndTeardownRefuseOlderAndFuturePublication() throws {
        let owner = MarkdownParseAuthority()
        let first = try #require(owner.ticket())
        owner.invalidatePresentation()
        #expect(!owner.admits(first))
        let second = try #require(owner.ticket())
        owner.tearDown()
        #expect(!owner.admits(second))
        #expect(owner.ticket() == nil)
    }

    @Test func anotherEditorLifetimeCannotPublishHere() throws {
        let first = MarkdownParseAuthority()
        let second = MarkdownParseAuthority()
        let ticket = try #require(first.ticket())
        #expect(!second.admits(ticket))
    }
}

@MainActor
private final class AuthoritySourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
