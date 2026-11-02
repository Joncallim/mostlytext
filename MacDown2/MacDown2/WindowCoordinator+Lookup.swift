import AppKit
import Foundation

extension WindowCoordinator {
    func controllerForDocument(
        url: URL,
        excluding excludedController: WindowController? = nil
    ) -> WindowController? {
        controllers.first {
            $0 !== excludedController && $0.model.tabStore.tabID(forFileURL: url) != nil
        }
    }

    /// Where "Open Folder" lands when the caller named no window: the key document window, else the
    /// frontmost document window (the key window can be Settings, a palette or the welcome window), else
    /// a new untitled window — choosing a folder must never silently do nothing.
    func folderTargetController(createIfNeeded: Bool = true) -> WindowController? {
        if let key = controllers.first(where: { $0.window == NSApp.keyWindow }) {
            return key
        }
        let ordered = NSApp.orderedWindows.compactMap { window in controllers.first { $0.window === window } }
        if let frontmost = ordered.first ?? controllers.last {
            return frontmost
        }
        guard createIfNeeded else { return nil }
        newDocument()
        return controllers.last
    }
}
