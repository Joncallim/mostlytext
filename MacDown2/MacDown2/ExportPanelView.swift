import AppKit
import ExportService
import FileCore
import SwiftUI
import UniformTypeIdentifiers

/// The selectable export format in the export panel.
enum ExportFormatOption: String, CaseIterable, Identifiable {
    case standaloneHTML
    case selfContainedHTML
    case pdf

    var id: String {
        rawValue
    }

    func title(locale: Locale, bundle: Bundle = .main) -> String {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        return switch self {
        case .standaloneHTML: String(localized: "HTML", bundle: bundle, locale: locale)
        case .selfContainedHTML: String(localized: "Self-contained HTML", bundle: bundle, locale: locale)
        case .pdf: String(localized: "PDF", bundle: bundle, locale: locale)
        }
    }

    /// The content type the save panel must enforce for this format, so the
    /// saved file's extension always matches what was actually written.
    var contentType: UTType {
        switch self {
        case .standaloneHTML, .selfContainedHTML: .html
        case .pdf: .pdf
        }
    }

    var fileExtension: String {
        contentType.preferredFilenameExtension ?? (self == .pdf ? "pdf" : "html")
    }

    /// Every extension the panel may have appended for some other format, so
    /// switching format replaces the extension instead of appending to it.
    static let knownExtensions = ["html", "htm", "pdf"]

    func explanation(locale: Locale, bundle: Bundle = .main) -> String? {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        return switch self {
        case .standaloneHTML: nil
        case .selfContainedHTML:
            String(localized: "Embeds the stylesheet and every image into one file that opens anywhere.",
                   bundle: bundle, locale: locale)
        case .pdf:
            String(localized: "Embeds every image and prints through the macOS render system.",
                   bundle: bundle, locale: locale)
        }
    }
}

/// The user's in-panel export choices. Held by reference so the coordinator can
/// read the final values after the save panel closes.
@MainActor
@Observable
final class ExportSelectionModel {
    var format: ExportFormatOption
    var style: ExportStyleEmbedding

    init(format: ExportFormatOption = .standaloneHTML, style: ExportStyleEmbedding = .embedded) {
        self.format = format
        self.style = style
    }
}

/// The export panel (Slice 5): format and, for standalone HTML, CSS style. It is
/// hosted as the `NSSavePanel` accessory view, matching the legacy MacDown
/// export panel accessory without importing any of its Objective-C.
struct ExportPanelView: View {
    @Environment(\.locale) private var locale
    @Bindable var model: ExportSelectionModel
    var allowsLinkedStyle = true
    /// Called when the format changes so the save panel's filename extension and
    /// allowed content type can follow the selection.
    var onFormatChange: (ExportFormatOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Format", selection: $model.format) {
                ForEach(ExportFormatOption.allCases) { option in
                    Text(verbatim: option.title(locale: locale)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Export format")

            if model.format == .standaloneHTML, allowsLinkedStyle {
                Picker("Style", selection: $model.style) {
                    Text("Embedded CSS").tag(ExportStyleEmbedding.embedded)
                    Text("Linked CSS").tag(ExportStyleEmbedding.linked)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Stylesheet delivery")
            } else if let explanation = model.format.explanation(locale: locale) {
                Text(verbatim: explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .frame(width: 380, alignment: .leading)
        .onChange(of: model.format) { _, newValue in
            onFormatChange(newValue)
        }
    }
}
