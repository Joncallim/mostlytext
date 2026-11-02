import AppSettings
import FileTree
import SwiftUI

/// Launch behavior plus the folder-browser preferences that already exist
/// as typed, persisted state (`FileTree.FileTreePreferences`) but have had
/// no settings UI until now — this pane presents them directly rather than
/// re-homing their storage (planning/epic-13-implementation.md §5).
struct GeneralSettingsPane: View {
    @Environment(\.appSettings) private var appSettings
    @Environment(\.windowCoordinator) private var coordinator

    var body: some View {
        if let appSettings, let coordinator {
            GeneralSettingsForm(appSettings: appSettings, fileTreePreferences: coordinator.fileTreePreferences)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
        }
    }
}

private struct GeneralSettingsForm: View {
    @Bindable var appSettings: AppSettingsModel
    @Bindable var fileTreePreferences: FileTreePreferences

    var body: some View {
        Form {
            Section {
                Picker("On launch:", selection: $appSettings.general.launchBehavior) {
                    Text("Reopen windows from last session").tag(GeneralSettings.LaunchBehavior.restorePreviousSession)
                    Text("Start with a new document").tag(GeneralSettings.LaunchBehavior.startWithNewDocument)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Launch behavior")
            }

            Section("Folder Browser") {
                Toggle("Show hidden files", isOn: $fileTreePreferences.filter.showsHiddenFiles)
                Toggle("Open items with a single click", isOn: $fileTreePreferences.opensOnSingleClick)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
