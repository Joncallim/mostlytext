import AppKit
import SwiftUI
import TextFilters

/// The "Commands" menu: discovered user text filters, plus the two
/// deliberately manual affordances issue #15/epic-14-implementation.md §1
/// calls for instead of auto-installing anything — "Show Commands Folder"
/// and "Add Example Scripts". A separate `Commands` conformance from
/// `WorkspaceCommands`, composed alongside it in `MacDown2App`, so this
/// menu's discovery logic stays independently readable and neither file
/// grows toward SwiftLint's `type_body_length` budget.
struct TextFilterCommands: Commands {
    @Environment(\.windowCoordinator) private var coordinator

    var body: some Commands {
        CommandMenu("Commands") {
            Button("Command Palette…") {
                coordinator?.toggleCommandPalette()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            let commands = coordinator
                .map { TextFilterCommandDiscovery.discoverCommands(in: $0.commandsDirectory) } ?? []
            if commands.isEmpty {
                Text("No Commands Installed")
            } else {
                ForEach(commands) { command in
                    Button(command.name) {
                        Task { await coordinator?.textFilterCoordinator.run(command) }
                    }
                    .accessibilityIdentifier("textFilterCommand.\(command.id)")
                }
                .disabled(coordinator?.textFilterCoordinator.canRunTextFilters != true)
            }

            Divider()

            Button("Show Commands Folder") {
                guard let directory = coordinator?.commandsDirectory else { return }
                // Discovery creates the directory as a side effect (§9); the
                // folder must exist before Finder can open it.
                _ = TextFilterCommandDiscovery.discoverCommands(in: directory)
                NSWorkspace.shared.open(directory)
            }

            Button("Add Example Scripts") {
                guard let directory = coordinator?.commandsDirectory else { return }
                let result = BundledExampleScripts.install(into: directory)
                Self.presentAddExampleScriptsResult(result)
            }
        }
    }

    /// `install(into:)` runs silently by design (it may run repeatedly as
    /// the user reopens this menu) but its *result* was never surfaced at
    /// all — a user clicking this had no way to tell whether it had done
    /// anything, short of separately opening "Show Commands Folder" to
    /// check (manual verification finding). A plain, undismissable-window
    /// `NSAlert` is deliberately not sheeted on any particular document
    /// window: unlike a text filter's failure, this action has no single
    /// originating window to sheet against.
    ///
    /// `hadFailure` is reported as its own case — separate from "zero
    /// installed" — because a permission, disk-full, or other filesystem
    /// failure previously collapsed into the exact same "already
    /// installed" message a genuinely no-op run produces, hiding a real
    /// error behind a reassuring one (Codex review finding, PR #56).
    private static func presentAddExampleScriptsResult(_ result: BundledExampleScripts.InstallResult) {
        let alert = NSAlert()
        if result.hadFailure {
            alert.alertStyle = .warning
            alert.messageText = result.installedCount > 0
                ? String(localized: "Some Example Scripts Couldn't Be Added")
                : String(localized: "Couldn't Add Example Scripts")
            alert.informativeText = String(
                localized: "Check that MostlyText can write to the Commands folder, then try again."
            )
        } else if result.installedCount > 0 {
            alert.alertStyle = .informational
            alert.messageText = installedExamplesTitle(count: result.installedCount)
            alert.informativeText = String(localized: "They're now listed in the Commands menu.")
        } else {
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Example Scripts Already Installed")
            alert.informativeText = String(
                localized: "Nothing new to add — see \"Show Commands Folder\" for what's there."
            )
        }
        alert.runModal()
    }

    static func installedExamplesTitle(count: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(AttributedString(
            localized: "^[Added \(count) Example Script](inflect: true)", bundle: bundle, locale: locale
        ).characters)
    }
}
