import AppSettings
import SwiftUI

struct MarkdownSettingsPane: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        if let appSettings {
            MarkdownSettingsForm(appSettings: appSettings)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
        }
    }
}

private struct MarkdownSettingsForm: View {
    @Bindable var appSettings: AppSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Parse block directives (`@Name { … }`)", isOn: $appSettings.markdown.parsesBlockDirectives)
            } footer: {
                Text(
                    """
                    Tables, task lists, and strikethrough always parse and cannot be turned off. Autolinks are \
                    recognised only in <https://…> form, and footnotes are not supported yet. Block directives affect \
                    document structure; Preview and exports render their source as ordinary Markdown, without DocC \
                    callout styling. An unfinished directive falls back to ordinary Markdown if it would hide content.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
