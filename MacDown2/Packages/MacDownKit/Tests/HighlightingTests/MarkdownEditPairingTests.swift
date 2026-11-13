import AppKit
import EditorCore
@testable import Highlighting
import SwiftUI
import Testing

@MainActor
@Suite("Markdown edit pairing")
struct MarkdownEditPairingTests {
    @Test func realEditorAndStorageCallbacksPairOneReplacement() throws {
        let original = "alpha 😀\r\nbeta"
        let model = SourceBox(original)
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
        let pair = MarkdownEditPairing<String>()
        let target = (original as NSString).range(of: "beta")
        system.preEditObserver = { range, replacement, oldSource in
            pair.prepare(range: range, replacement: replacement, oldSource: oldSource) { source, oldRange, _ in
                source.substring(with: oldRange)
            }
        }
        var match: MarkdownEditPairing<String>.Match?
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            match = pair.complete(editedRange: range, delta: delta, postSource: storage.mutableString)
        }

        system.textView.insertText("gamma", replacementRange: target)

        #expect(match?.candidate == "beta")
        #expect(match?.oldRange == target)
        #expect(match?.newRange == NSRange(location: target.location, length: 5))
        #expect(model.text == "alpha 😀\r\ngamma")
    }

    @Test func exactMountedReplacementPairsOldAndNewUTF16Geometry() throws {
        let original = "alpha 😀\r\nbeta"
        let store = EditorTextSystemStore()
        let system = store.system(for: UUID().uuidString, initialText: original, configuration: .default)
        let storage = try #require(system.textView.textStorage)
        let gate = HighlightingStorageGate()
        gate.install(on: storage)
        defer { gate.uninstall(from: storage) }
        let pair = MarkdownEditPairing<String>()
        let oldRange = (original as NSString).range(of: "beta")
        pair.prepare(range: oldRange, replacement: "gamma", oldSource: storage.mutableString) { source, range, _ in
            source.substring(with: range)
        }
        var match: MarkdownEditPairing<String>.Match?
        gate.didProcessCharacterEditWithGeometry = { range, delta, _ in
            match = pair.complete(editedRange: range, delta: delta, postSource: storage.mutableString)
        }

        storage.replaceCharacters(in: oldRange, with: "gamma")

        #expect(match?.candidate == "beta")
        #expect(match?.oldRange == oldRange)
        #expect(match?.newRange == NSRange(location: oldRange.location, length: 5))
        #expect(match?.delta == 1)
        #expect(pair.complete(editedRange: oldRange, delta: 0, postSource: storage.mutableString)?.candidate == nil)
    }

    @Test func nestedOrVetoedProposalCannotAuthorizeLaterEdit() {
        let pair = MarkdownEditPairing<String>()
        let old = "one two" as NSString
        let first = old.range(of: "one")
        let second = old.range(of: "two")
        pair.prepare(range: first, replacement: "ONE", oldSource: old) { _, _, _ in "first" }
        pair.prepare(range: second, replacement: "TWO", oldSource: old) { _, _, _ in "second" }
        #expect(pair.complete(editedRange: second, delta: 0, postSource: "one TWO" as NSString)?.candidate == nil)
        pair.prepare(range: second, replacement: "TWO", oldSource: old) { _, _, _ in "fresh" }
        #expect(pair.complete(editedRange: second, delta: 0, postSource: "one TWO" as NSString)?.candidate == "fresh")

        pair.prepare(range: first, replacement: "ONE", oldSource: old) { _, _, _ in nil }
        pair.prepare(range: second, replacement: "TWO", oldSource: old) { _, _, _ in "nested" }
        #expect(pair.complete(editedRange: second, delta: 0, postSource: "one TWO" as NSString)?.candidate == nil)
        pair.prepare(range: second, replacement: "TWO", oldSource: old) { _, _, _ in "after-rejection" }
        #expect(pair.complete(editedRange: second, delta: 0, postSource: "one TWO" as NSString)?
            .candidate == "after-rejection")
    }

    @Test func unobservedAndMismatchedEditsFailClosed() {
        let pair = MarkdownEditPairing<String>()
        let old = "alpha beta" as NSString
        let range = old.range(of: "beta")
        let new = "alpha gamma" as NSString
        #expect(pair.complete(editedRange: .init(location: range.location, length: 5),
                              delta: 1, postSource: new)?.candidate == nil)
        pair.prepare(range: range, replacement: "gamma", oldSource: old) { _, _, _ in "candidate" }
        #expect(pair.complete(editedRange: .init(location: range.location, length: 5),
                              delta: 0, postSource: new)?.candidate == nil)
        #expect(pair.complete(editedRange: .init(location: range.location, length: 5),
                              delta: 1, postSource: new)?.candidate == nil)
        pair.prepare(range: range, replacement: "gamma", oldSource: old) { _, _, _ in "candidate" }
        #expect(pair.complete(editedRange: .init(location: range.location, length: 5),
                              delta: 1, postSource: "alpha gaMma" as NSString)?.candidate == nil)

        pair.prepare(range: range, replacement: String(repeating: "x", count: 65537), oldSource: old) { _, _, _ in
            "oversized"
        }
        #expect(pair.complete(editedRange: range, delta: 0, postSource: old)?.candidate == nil)
    }
}

@MainActor
private final class SourceBox {
    var text: String

    init(_ text: String) {
        self.text = text
    }
}
