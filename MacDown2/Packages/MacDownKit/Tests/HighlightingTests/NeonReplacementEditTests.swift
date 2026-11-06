import AppKit
import Foundation
@testable import Highlighting
import Testing

/// Register row H5: highlights after an edit must equal what a fresh
/// highlighter produces for the same text.
///
/// Selection replacement now has strict parser-range and client-invalidation
/// regressions. The text-view check below must also match a fresh highlighter.
/// Rapid typing followed by a block deletion also has a strict buffer-coordinate
/// regression. The widened background experiment remains
/// guarded by its recorded Debug abort until separately qualified.
@MainActor
@Suite(.serialized)
struct NeonReplacementEditTests {
    private static let text = StallFixtures.markdown(utf8Bytes: 48 * 1024)

    private func runs(afterEditing editor: HighlightedEditor) async throws
        -> (edited: [RenderedRun], fresh: [RenderedRun]) {
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(3)))
        let fresh = HighlightedEditor(text: editor.textView.string)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .seconds(2)))
        return (editor.renderedRuns(), fresh.renderedRuns())
    }

    private func editor() async throws -> HighlightedEditor {
        let editor = HighlightedEditor(text: Self.text)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(2)))
        return editor
    }

    private func typeRapidly(in editor: HighlightedEditor) {
        let middle = Self.text.utf16.count / 2
        for index in 0 ..< 11 {
            editor.typeOrDelete(at: middle, insert: index.isMultiple(of: 2))
        }
    }

    @Test func rapidTypingMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        typeRapidly(in: editor)

        let (edited, fresh) = try await runs(afterEditing: editor)
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    @Test func deletingABlockMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        editor.textView.insertText("", replacementRange: NSRange(location: 1000, length: 1500))

        let (edited, fresh) = try await runs(afterEditing: editor)
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    /// The same two edit kinds in one main-actor turn (no await between them)
    /// must retain repaint ownership near the original typing location.
    @Test func typingThenDeletingABlockInOneTurnMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        typeRapidly(in: editor)
        editor.textView.insertText("", replacementRange: NSRange(location: 1000, length: 1500))

        let (edited, fresh) = try await runs(afterEditing: editor)
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    @Test func replacingASelectionContainingInlineRangesMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        // Paste over a 600-unit selection (below Neon's 2,048 threshold, so
        // this is the synchronous path) with text that contains inline markup.
        let range = NSRange(location: Self.text.utf16.count / 2, length: 600)
        let replacement = (Self.text as NSString).substring(with: range) + "y"
        editor.textView.insertText(replacement, replacementRange: range)

        let (edited, fresh) = try await runs(afterEditing: editor)
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    /// Release only: in Debug the widened experiment aborts the test host with
    /// SwiftTreeSitter's `assertionFailure("location is greater than end")`
    /// (`String+Data.swift:20`) — it makes that stale-read path routine.
    @Test(.enabled(if: !isDebugBuild))
    func widenedBackgroundTypingMatchesAFreshHighlighter() async throws {
        let editor = HighlightedEditor(text: Self.text, widensEdits: true)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(2)))
        typeRapidly(in: editor)

        let (edited, fresh) = try await runs(afterEditing: editor)
        // Optimized native qualification now demonstrates parity. Keep this
        // strict; the separately recorded Debug abort remains gated above.
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    @Test func wideningIsATruthfulInBoundsDescription() {
        let widen = EditWideningStorageDelegate.widen
        // A one-character insert in the middle: old range grows to 2,048, to the left.
        #expect(widen(NSRange(location: 5000, length: 1), 1, 10000) == NSRange(location: 2952, length: 2049))
        // Near the start: what does not fit on the left goes to the right.
        #expect(widen(NSRange(location: 10, length: 1), 1, 10000) == NSRange(location: 0, length: 2049))
        // A deletion (post-edit length 0, delta -5): old length 5 → 2,048.
        #expect(widen(NSRange(location: 4000, length: 0), -5, 10000) == NSRange(location: 1957, length: 2043))
        // Already large, or a document too short to widen: unchanged.
        #expect(widen(NSRange(location: 0, length: 3000), 0, 10000) == NSRange(location: 0, length: 3000))
        #expect(widen(NSRange(location: 3, length: 1), 1, 100) == NSRange(location: 3, length: 1))
    }
}

private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()
