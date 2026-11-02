import AppKit
import AppSettings
import SwiftUI

/// Keep an explicit way to continue while the normal document owners do not
/// yet exist. Closing a placeholder must not dismiss the import accidentally.
@MainActor
final class LegacyImportWindowController: NSWindowController, NSWindowDelegate {
    init(startup: ApplicationMigrationStartup) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 540),
                              styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "MacDown Preferences")
        window.contentView = NSHostingView(rootView: ApplicationMigrationView(startup: startup))
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        false
    }
}
