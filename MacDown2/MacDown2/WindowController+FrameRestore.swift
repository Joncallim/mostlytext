import AppKit
import Foundation

extension WindowController {
    static let frameAutosaveName = "MacDown2DocumentWindow"

    /// Whether AppKit already has a saved frame for `name` (`NSWindow Frame <name>`), i.e. whether
    /// `setFrameAutosaveName` is about to restore a size rather than leave the window at its default.
    static func hasSavedFrame(named name: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: "NSWindow Frame \(name)") != nil
    }

    /// Restores the saved frame, or gives a window with none (first launch, or an autosave name already in use by
    /// another window) the default size. Setting the size unconditionally shrank a restored window and re-saved that.
    static func restoreFrame(of window: NSWindow) {
        #if UITEST_ISOLATED
            // Never read or write bundle-keyed AppKit window frame preferences.
            window.setContentSize(NSSize(width: 1200, height: 800))
            return
        #else
            let hadSavedFrame = hasSavedFrame(named: frameAutosaveName)
            let restored = window.setFrameAutosaveName(frameAutosaveName) && hadSavedFrame
            if !restored {
                window.setContentSize(NSSize(width: 1200, height: 800))
            }
        #endif
    }
}
