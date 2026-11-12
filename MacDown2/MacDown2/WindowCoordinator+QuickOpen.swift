import AppKit

/// The ⌘P Quick Open panel (EPIC-22 §6.15, Slice 6b). Split out of
/// `WindowCoordinator.swift`'s main class body, matching
/// `WindowCoordinator+CommandPalette.swift`/`WindowCoordinator+GoToLine.swift`'s
/// same reason (SwiftLint's `type_body_length` budget).
extension WindowCoordinator {
    /// Shows Quick Open for the key window's active folder root, or closes
    /// it if one is already open. Like `GoToLinePanel` and unlike the
    /// command palette, this panel has nothing useful to do without a
    /// folder root to search — `WorkspaceFileIndex` is per-window (§6.15),
    /// so it does not open at all when the key window has no folder open,
    /// matching Go to Line's own "no live editor, don't open" precedent
    /// rather than opening into a guaranteed-empty state.
    func toggleQuickOpen() {
        if let existing = quickOpen {
            existing.close()
            return
        }

        let originWindow = NSApp.keyWindow
        guard let originController = controllers.first(where: { $0.window == originWindow }),
              originController.currentQuickOpenOrigin != nil
        else { return }

        let created = QuickOpenPanel(
            coordinator: self,
            originController: originController,
            index: originController.workspaceFileIndex
        )
        // Strong ownership lives here for exactly as long as the panel is
        // open; `quickOpenDidClose` releases it. See `QuickOpenPanel`'s own
        // doc comment for why this reference must exist at all.
        quickOpen = created

        if let originWindow {
            let origin = NSPoint(
                x: originWindow.frame.midX - created.frame.width / 2,
                y: min(originWindow.frame.maxY - 120, originWindow.frame.midY + 150)
            )
            created.setFrameOrigin(origin)
        } else {
            created.center()
        }
        // Same activation dance as `toggleCommandPalette`/`toggleGoToLine`
        // — see `toggleCommandPalette`'s own doc comment for why
        // `makeKeyAndOrderFront` alone is insufficient and why the
        // deferral plus identity re-check (against a panel already closed
        // or superseded by the time this runs) matter.
        DispatchQueue.main.async { [weak self] in
            guard let self, quickOpen === created else { return }
            NSApp.activate(ignoringOtherApps: true)
            created.makeKeyAndOrderFront(nil)
            created.orderFrontRegardless()
        }
    }

    /// Called by `QuickOpenPanel.windowWillClose`. Releases the
    /// coordinator's strong reference so a closed panel is freed rather
    /// than kept alive indefinitely, and so a later `toggleQuickOpen()`
    /// creates a fresh panel instead of finding a defunct one.
    func quickOpenDidClose(_ panel: QuickOpenPanel) {
        guard quickOpen === panel else { return }
        quickOpen = nil
    }

    /// Closes Quick Open if it is open against `controller`, called from
    /// `WindowController.setFileTreeRoot(_:accessURL:)` whenever that
    /// controller's folder root changes — not just when the controller
    /// itself closes (`removeController`'s own, separate guard, for the
    /// window-closing case). An independent hostile review of this slice
    /// found that without this, switching an already-open window to a
    /// different folder (Open Folder…, Open Recent Folder, or session
    /// restore) while Quick Open was still showing results from the OLD
    /// root left `quickOpen` open and pointing at a `WorkspaceFileIndex`
    /// that had just been rebuilt for the NEW root: resolving an
    /// already-selected, now-stale result's `relativePath` against the new
    /// root could silently open the wrong file, or fail with no visible
    /// error. Closing outright, rather than trying to keep the panel open
    /// but refreshed, matches `removeController`'s own "just close it"
    /// choice for the equivalent window-closing case — reopening Quick
    /// Open fresh against the new root is unambiguous, a silently
    /// re-filtered result set is not.
    func closeQuickOpenIfOrigin(_ controller: WindowController) {
        guard quickOpen?.originController === controller else { return }
        quickOpen?.close()
    }
}
