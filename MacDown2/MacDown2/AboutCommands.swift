import AppKit
import SwiftUI

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MostlyText") { openWindow(id: "about") }
            Button("Open Source Licenses…") { openWindow(id: "licenses") }
        }
        CommandGroup(after: .help) {
            Button("Open Source Licenses…") { openWindow(id: "licenses") }
        }
    }
}

struct AboutMostlyTextView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("MostlyText")
                .font(.largeTitle)
                .textSelection(.enabled)
            LabeledContent("Version", value: Self.version)
                .fixedSize()
            Text("An editor descended from MacDown. Free software under the MIT license.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Source Licenses…") { openWindow(id: "licenses") }
                .accessibilityIdentifier("about.openSourceLicenses")
        }
        .padding(28)
        .frame(width: 380)
    }

    private static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
