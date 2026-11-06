import AppKit
import Foundation
import SwiftUI
@testable import Textual

extension SecuredMarkdownMountedTests {
    /// Failure-only readback of the actual selection model and current layout. Never repairs or replaces it.
    func attachmentLayoutDiagnostics(in view: NSView) -> String {
        guard let native = view as? Textual.NSTextInteractionView else {
            return "actual Textual selection type unavailable"
        }
        let model = native.model
        let selected = model.selectedRange.map { model.attributedText(in: $0) }
        let collection = Mirror(reflecting: model).children.compactMap {
            $0.value as? any TextLayoutCollection
        }.first
        guard let collection else {
            return "actual layout collection unavailable; selection=\(attachmentAttributes(selected))"
        }
        let layouts = collection.layouts.enumerated().map { index, layout in
            let cached = attachmentAttributes(layout.attributedString)
            guard let live = layout as? LiveTextLayout else {
                return "layout=\(index) cached=\(cached) type=\(type(of: layout))"
            }
            let current = live.base.materializeContents()
            let attachmentRuns = live.base.reduce(0) { count, line in
                count + line.filter { $0.attachment != nil }.count
            }
            let fresh = current.attributedStrings.map { attachmentAttributes($0) }.joined(separator: " / ")
            return "layout=\(index) cached=\(cached) lines=\(live.base.count) "
                + "lineFragments=\(current.lineFragments.count) actualAttachmentRuns=\(attachmentRuns) fresh=\(fresh)"
        }.joined(separator: " | ")
        return "selection=\(attachmentAttributes(selected)); \(layouts)"
    }

    private func attachmentAttributes(_ attributed: NSAttributedString?) -> String {
        guard let attributed else { return "none" }
        var attachments = 0
        let range = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.textual.attachment, in: range) { value, _, _ in
            if value != nil {
                attachments += 1
            }
        }
        let bridged = try? AttributedString(attributed, including: \.textual)
        let copySizes = bridged?.attachments().map { attachment in
            attachment.boundedPNGData(maxBytes: 1024 * 1024)?.count ?? -1
        }.sorted() ?? []
        return "text=\(attributed.string.debugDescription) attachmentRanges=\(attachments) "
            + "actualAttachmentBoundedPNGBytes=\(copySizes)"
    }
}
