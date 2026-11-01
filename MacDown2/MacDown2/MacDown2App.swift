import AppSettings
import SwiftUI
import Themes

@main
struct MacDown2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .commands {
            WorkspaceCommands(themeController: appDelegate.themeController)
            TextFilterCommands()
        }
        .environment(\.windowCoordinator, appDelegate.coordinator)
        .environment(\.themeController, appDelegate.themeController)
        .environment(\.appSettings, appDelegate.appSettings)

        Settings {
            SettingsView()
                .environment(\.appSettings, appDelegate.appSettings)
                .environment(\.windowCoordinator, appDelegate.coordinator)
                .environment(\.themeController, appDelegate.themeController)
                .environment(\.themeCatalog, appDelegate.themeCatalog)
        }
    }
}
