import AppKit
import SwiftUI

struct ApplicationMigrationView: View {
    let startup: ApplicationMigrationStartup

    var body: some View {
        switch startup.phase {
        case .optionalImport:
            if let optional = startup.optionalImport {
                LegacyImportStartupView(startup: optional)
            }
        case .migrating:
            ProgressView("Preserving your previous installation…").padding(40).frame(width: 590, height: 250)
        case .preservedReview:
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Existing MostlyText Installation Was Kept").font(.title2)
                Text(
                    LocalizedStringKey("The previous development installation was preserved separately, "
                        + "including its unsaved recovery files.")
                )
                Button("Show Preserved Installation") { showPreserved() }
                Button("Continue With Existing Installation") {
                    Task { await startup.continueWithCurrentInstallation() }
                }.keyboardShortcut(.defaultAction)
            }.padding(24).frame(width: 540)
        case .blocked:
            VStack(alignment: .leading, spacing: 16) {
                Text("Installation Needs Review").font(.title2)
                Text(
                    LocalizedStringKey("Close older installations before retrying. "
                        + "Existing files, preferences and recovery copies are preserved.")
                )
                Text("Unsupported or changed state must be reviewed before this version can open it safely.")
                if startup.reviewDirectory != nil {
                    Button("Show Preserved Installation") { showPreserved() }
                }
                HStack {
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Retry Migration") { Task { await startup.begin() } }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).frame(width: 540)
        case .ready: EmptyView()
        }
    }

    private func showPreserved() {
        if let url = startup.reviewDirectory {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
