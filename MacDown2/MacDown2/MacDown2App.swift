import AppSettings
import SwiftUI
import Themes

@main
struct MacDown2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        ApplicationScenes(appDelegate: appDelegate)
    }
}

/// Observe deferred migration readiness where scenes and commands consume it.
/// The delegate adaptor owns lifetime; it does not observe this App's captured values.
private struct ApplicationScenes: Scene {
    @ObservedObject var appDelegate: AppDelegate

    var body: some Scene {
        let ready = appDelegate.normalLaunchReady
        WindowGroup {
            StartupPlaceholderView()
                .frame(width: 0, height: 0)
        }
        // The delegate selects migration, Welcome and document windows. An
        // automatic placeholder would persist frame state before migration.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
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
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Open Source Licenses", id: "licenses") {
            LicenseNoticesView()
        }
        .defaultSize(width: 760, height: 600)
        .defaultLaunchBehavior(.suppressed)
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
