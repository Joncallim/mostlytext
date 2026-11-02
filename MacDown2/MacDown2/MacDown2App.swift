import AppSettings
import SwiftUI
import Themes

@main
struct MacDown2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let ready = appDelegate.normalLaunchReady
        WindowGroup {
            EmptyView()
        }
        .commands {
            if ready, let themeController = appDelegate.themeController {
                WorkspaceCommands(themeController: themeController)
                TextFilterCommands()
                AboutCommands()
            }
        }
        .environment(\.windowCoordinator, ready ? appDelegate.coordinator : nil)
        .environment(\.themeController, ready ? appDelegate.themeController : nil)
        .environment(\.appSettings, ready ? appDelegate.appSettings : nil)

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
            Group {
                if ready {
                    SettingsView()
                } else {
                    ApplicationMigrationView(startup: appDelegate.startup)
                }
            }
            .environment(\.appSettings, ready ? appDelegate.appSettings : nil)
            .environment(\.windowCoordinator, ready ? appDelegate.coordinator : nil)
            .environment(\.themeController, ready ? appDelegate.themeController : nil)
            .environment(\.themeCatalog, appDelegate.themeCatalog)
        }
    }
}
