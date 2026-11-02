import AppKit
import TextFilters

/// The ⌘⇧P command palette (epic-14-implementation.md §17 Slice 7). Split
/// out of `WindowCoordinator.swift`'s main class body to stay under the
/// `type_body_length` lint budget, matching
/// `WindowCoordinator+SessionRestore.swift`'s same reason.
extension WindowCoordinator {
    /// Shows the command palette, or closes it if one is already open.
    ///
    /// The origin window — whatever is key *before* the palette is
    /// created — is captured once here and threaded through to every
    /// command the palette can invoke. The palette panel itself becomes
    /// the key window as soon as it is shown, so anything that resolved
    /// its target from `NSApp.keyWindow` at invocation time would silently
    /// act on the palette instead of the document window the user actually
    /// meant (post-review finding #7).
    func toggleCommandPalette() {
        if let existing = commandPalette {
            existing.close()
            return
        }

        let originWindow = NSApp.keyWindow
        let originController = controllers.first(where: { $0.window == originWindow })
        let directory = commandsDirectory
        let created = CommandPalettePanel(coordinator: self, originController: originController,
                                          discoverTextFilters: {
                                              TextFilterCommandDiscovery.discoverCommands(in: directory)
                                          })
        // Strong ownership lives here for exactly as long as the panel is
        // open; `commandPaletteDidClose` releases it. See
        // `CommandPalettePanel`'s doc comment for why this reference must
        // exist at all (post-review finding #6).
        commandPalette = created

        if let originWindow {
            let origin = NSPoint(
                x: originWindow.frame.midX - created.frame.width / 2,
                y: min(originWindow.frame.maxY - 120, originWindow.frame.midY + 150)
            )
            created.setFrameOrigin(origin)
        } else {
            created.center()
        }
        // `makeKeyAndOrderFront` alone was not sufficient (manual
        // verification finding): the panel opens but does not visibly take
        // over — not accepting typing/arrow-key navigation, or not truly
        // frontmost, until manually clicked. `activate(ignoringOtherApps:)`
        // plus `orderFrontRegardless()` is the combination AppKit apps that
        // need a floating panel to reliably seize real keyboard focus (a
        // launcher/palette being the canonical case) use, since either call
        // alone can be insufficient depending on the app's current
        // activation state.
        //
        // Deferred one run-loop turn: `contentView` was just assigned a
        // brand-new `NSHostingView` above, and SwiftUI has not yet run its
        // first update pass — the search field's `@FocusState` is set from
        // `CommandPaletteView.onAppear`, which fires *during* that first
        // pass. Ordering the window front synchronously, in the same turn,
        // races that: the window can become key before `@FocusState` has
        // anything to attach a first responder to. Deferring gives SwiftUI
        // that pass first, so the window becoming key already reflects the
        // field wanting focus, rather than the two racing.
        //
        // That same deferral is a window for `created` to already be stale
        // by the time this runs — closed by the user, superseded by a
        // second toggle, or closed as a side effect of its origin window
        // closing (`removeController`, below). Any of those already ran
        // `close()`, which synchronously clears `commandPalette` via
        // `commandPaletteDidClose`. Re-checking identity here is what stops
        // this block from ordering a closed, untracked panel back to the
        // front — one the next toggle would have no way to find and close
        // (Codex review finding, PR #56).
        DispatchQueue.main.async { [weak self] in
            guard let self, commandPalette === created else { return }
            NSApp.activate(ignoringOtherApps: true)
            created.makeKeyAndOrderFront(nil)
            created.orderFrontRegardless()
        }
    }

    /// Called by `CommandPalettePanel.windowWillClose`. Releases the
    /// coordinator's strong reference so a closed panel is freed rather
    /// than kept alive indefinitely, and so a later `toggleCommandPalette()`
    /// creates a fresh panel instead of finding a defunct one
    /// (post-review finding #6).
    func commandPaletteDidClose(_ panel: CommandPalettePanel) {
        guard commandPalette === panel else { return }
        commandPalette = nil
    }

    /// `true` if `controller` is still a controller this coordinator owns
    /// — i.e. its window has not been closed. Distinct from merely
    /// non-`nil`: a closed `WindowController` can still be alive in memory
    /// (something else may hold a reference to it) without being a live
    /// destination for any command (post-review finding #5).
    func isLiveController(_ controller: WindowController?) -> Bool {
        guard let controller else { return false }
        return controllers.contains { $0 === controller }
    }
}
