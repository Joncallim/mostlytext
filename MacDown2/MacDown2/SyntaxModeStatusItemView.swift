import FileCore
import SwiftUI

/// Inputs for the status bar's Syntax Mode indicator (EPIC-22, Slice 9d).
struct SyntaxModeStatusItem {
    struct Choice: Identifiable, Equatable {
        let id: String
        let name: String
    }

    /// The mode currently driving highlighting and editing behaviour.
    let effective: Choice
    /// What automatic detection resolves to for this document.
    let automatic: Choice
    let isOverridden: Bool
    let choices: [Choice]
    /// `nil` selects automatic detection.
    let onSelect: (String?) -> Void

    init(autoFormat: FileFormat, syntaxFormat: FileFormat, onSelect: @escaping (String?) -> Void) {
        automatic = Choice(id: autoFormat.id, name: autoFormat.name)
        effective = Choice(id: syntaxFormat.id, name: syntaxFormat.name)
        isOverridden = syntaxFormat.id != autoFormat.id
        choices = FileFormatRegistry.defaultFormats
            .map { Choice(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.onSelect = onSelect
    }
}

/// Shows the active syntax mode and lets the user pick a different one for
/// this document. Purely an editing aid: the file's format, preview and bytes
/// are never touched by the choice.
struct SyntaxModeStatusItemView: View {
    @Environment(\.locale) private var locale
    let item: SyntaxModeStatusItem

    var body: some View {
        Menu(item.effective.name) {
            Toggle(
                Self.automaticTitle(item.automatic.name, locale: locale),
                isOn: Binding(get: { !item.isOverridden }, set: { _ in item.onSelect(nil) })
            )
            Divider()
            ForEach(item.choices) { choice in
                Toggle(
                    choice.name,
                    isOn: Binding(
                        get: { item.isOverridden && item.effective.id == choice.id },
                        set: { _ in item.onSelect(choice.id) }
                    )
                )
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("statusBarSyntaxMode")
        .help("Syntax Mode")
    }

    static func automaticTitle(_ name: String, locale: Locale, bundle: Bundle = .main) -> String {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        return String(localized: "Auto-detect (\(name))", bundle: bundle, locale: locale)
    }
}
