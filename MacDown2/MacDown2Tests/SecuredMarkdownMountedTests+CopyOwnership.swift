import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Textual

extension SecuredMarkdownMountedTests {
    @Test func aNoWriteNativeCopyCannotReuseAnEarlierImage() throws {
        let originalPasteboard = snapshotPasteboard()
        defer { restorePasteboard(originalPasteboard) }
        let model = Textual.TextSelectionModel()
        let interaction = Textual.NSTextInteractionView(
            model: model, exclusionRects: [], openURL: OpenURLAction { _ in .discarded }
        )
        let window = makeMountedWindow(hosting: interaction)
        defer {
            model.selectionDidChange = nil
            windowDiagnostics.stop(window)
            window.orderOut(nil)
            window.close()
        }
        try #require(interaction.responds(to: NSSelectorFromString("selectAll:")))
        try #require(interaction.responds(to: NSSelectorFromString("copy:")))
        let staleHTML = try "<img src=\"data:image/png;base64,\(smallPNG().base64EncodedString())\">"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        try #require(pasteboard.setString(staleHTML, forType: .html))
        let seededGeneration = pasteboard.changeCount

        // Clear the real selection during selectAll, so actual Textual Copy takes
        // its no-selection return. This controls interleaving without a timed sleep.
        model.selectionDidChange = {
            model.selectionDidChange = nil
            model.selectedRange = nil
        }
        _ = interaction.perform(NSSelectorFromString("selectAll:"), with: nil)
        _ = interaction.perform(NSSelectorFromString("copy:"), with: nil)
        let oldHTML = pasteboard.string(forType: .html)
        try #require(oldHTML == staleHTML)
        try #require(pasteboard.changeCount == seededGeneration)

        model.selectionDidChange = {
            model.selectionDidChange = nil
            model.selectedRange = nil
        }
        let refusedHTML = freshNativeCopiedHTML(from: interaction)
        try #require(refusedHTML == nil)
        let refusedGeneration = pasteboard.changeCount
        try #require(refusedGeneration > seededGeneration)

        model.selectionDidChange = nil
        let freshHTML = try #require(freshNativeCopiedHTML(from: interaction))
        try #require(freshHTML != staleHTML)
        try #require(pasteboard.changeCount > refusedGeneration)
        print("NATIVE_COPY_OWNERSHIP oldAcceptedStale=true fixedRefusedNoWrite=true freshActualWrite=true "
            + "seeded=\(seededGeneration) refused=\(refusedGeneration) fresh=\(pasteboard.changeCount)")
    }
}
