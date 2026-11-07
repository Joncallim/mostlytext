import AppKit
import CryptoKit
import Foundation
import SwiftUI
@testable import Textual

/// Diagnostic branch only. Reads real renderer preferences without publishing SwiftUI state.
@MainActor
struct PreviewRenderedAttachmentTrace: ViewModifier {
    let loadID: UUID?

    func body(content: Content) -> some View {
        content.overlayTextLayoutCollection { collection in
            Color.clear.onChange(of: AnyTextLayoutCollection(collection), initial: true) {
                let values = collection.layouts.map(\.attributedString)
                PreviewRenderedAttachmentObservations.record(values, loadID: loadID)
            }
        }
    }
}

@MainActor
enum PreviewRenderedAttachmentObservations {
    private static var sequence = 0

    static func record(_ strings: [NSAttributedString], loadID: UUID?) {
        guard sequence < 256 else { return }
        sequence += 1
        let rows = strings.prefix(16).map(describe)
        print("PREVIEW_RENDERER_LAYOUT sample=\(sequence) load=\(loadID?.uuidString ?? "none") " +
            "layouts=\(strings.count) observed=\(rows.joined(separator: " | "))")
    }

    static func selection(_ view: NSView) -> String {
        guard let interaction = view as? NSTextInteractionView,
              let range = interaction.model.selectedRange
        else { return "native-selection=unavailable" }
        return "native-selection=" + describe(interaction.model.attributedText(in: range))
    }

    private static func describe(_ string: NSAttributedString) -> String {
        var attachments = 0
        var keys = Set<String>()
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, _, _ in
            keys.formUnion(attributes.keys.map(\.rawValue))
            if attributes[.textual.attachment] != nil {
                attachments += 1
            }
        }
        let digest = SHA256.hash(data: Data(string.string.utf8)).map { String(format: "%02x", $0) }.joined()
        return "chars=\(string.length) attachmentRuns=\(attachments) textSHA256=\(digest) " +
            "attributeKeys=\(keys.sorted().prefix(16).joined(separator: ","))"
    }
}
