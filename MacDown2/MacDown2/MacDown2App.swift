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
            AboutCommands()
        }
        .environment(\.windowCoordinator, appDelegate.coordinator)
        .environment(\.themeController, appDelegate.themeController)
        .environment(\.appSettings, appDelegate.appSettings)

        Window("About MostlyText", id: "about") {
            AboutMostlyTextView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Open Source Licenses", id: "licenses") {
            LicenseNoticesView()
        }
        .defaultSize(width: 760, height: 600)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(\.appSettings, appDelegate.appSettings)
                .environment(\.windowCoordinator, appDelegate.coordinator)
                .environment(\.themeController, appDelegate.themeController)
                .environment(\.themeCatalog, appDelegate.themeCatalog)
        }
    }
}
