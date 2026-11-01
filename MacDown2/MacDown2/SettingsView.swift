import SwiftUI

/// The `Settings { }` scene's pane container (`⌘,` / "MacDown 2 → Settings…").
struct SettingsView: View {
    static let contentSize = CGSize(width: 580, height: 480)
    @Environment(\.appSettings) private var appSettings
    @Environment(\.themeController) private var themeController

    var body: some View {
        VStack(spacing: 0) {
            settingsTabs
            if appSettings?.hasUnreadableSettings == true || themeController?.hasUnreadablePreferences == true {
                Divider()
                Text(
                    """
                    Some saved settings cannot be read. Changes to those settings last only until you quit; \
                    their saved originals are preserved.
                    """
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .accessibilityIdentifier("settingsPersistenceWarning")
            }
        }
        .frame(width: Self.contentSize.width)
    }

    private var settingsTabs: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettingsPane()
            }
            Tab("Editor", systemImage: "character.cursor.ibeam") {
                EditorSettingsPane()
            }
            Tab("Markdown", systemImage: "text.badge.checkmark") {
                MarkdownSettingsPane()
            }
            Tab("Preview & Export", systemImage: "eye") {
                PreviewExportSettingsPane()
            }
            Tab("Formats", systemImage: "tablecells") {
                FormatSettingsPane()
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    }
}
