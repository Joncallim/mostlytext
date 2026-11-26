import AppKit
import SwiftUI
import TextFilters

/// A borderless, floating panel hosting `CommandPaletteView`
/// (epic-14-implementation.md §17 Slice 7).
///
/// Ownership (post-review finding #6): `NSPanel`'s `isReleasedWhenClosed`
/// defaults to `false` — unlike many `NSWindow`s, AppKit does **not**
/// deallocate this panel on its own when it closes, so something must hold
/// a strong reference for exactly as long as the panel should exist.
/// `WindowCoordinator` is that owner (`commandPalette` in
/// `WindowCoordinator+CommandPalette.swift`); this panel is its own
/// delegate purely to notify the coordinator when it closes
/// (`commandPaletteDidClose`), so that strong reference is released and a
/// closed panel is never mistaken for a reusable, still-open one. The panel
/// holds only a `weak` reference back to the coordinator, so there is no
/// retain cycle: coordinator → panel is the only strong edge.
@MainActor
final class CommandPalettePanel: NSPanel, NSWindowDelegate {
    private weak var coordinator: WindowCoordinator?
    /// The window this palette was opened from, so `WindowCoordinator` can
    /// close this panel the instant that window closes rather than leaving
    /// it open with a now-stale, no-longer-`controllers`-member origin
    /// (post-review finding #5) — see `removeController(_:)`.
    private(set) weak var originController: WindowController?

    convenience init(
        coordinator: WindowCoordinator,
        originController: WindowController?,
        appCommands: [AppPaletteCommand]? = nil,
        locale: Locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier),
        discoverTextFilters: @escaping () -> [TextFilterCommand] = { TextFilterCommandDiscovery.discoverCommands() }
    ) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.coordinator = coordinator
        self.originController = originController
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        delegate = self

        let model = CommandPaletteModel(
            appCommands: appCommands ?? AppPaletteCommand.standard(locale: locale),
            discoverTextFilters: discoverTextFilters,
            isAppCommandAvailable: { [weak coordinator, weak originController] command in
                guard let coordinator else { return false }
                return command.isAvailable(coordinator, originController)
            },
            // A live closure, not a value captured once at panel-open
            // (post-review finding #5): the origin's editing target can
            // stop existing while the palette stays open (its window
            // closing, or the active tab losing its editor), and this must
            // reflect that on every row rebuild rather than keep showing
            // filter rows that would silently no-op.
            textFiltersAvailable: { [weak coordinator, weak originController] in
                guard let coordinator, let originController else { return false }
                return coordinator.textFilterCoordinator.editingTarget(for: originController) != nil
            }
        )
        let view = CommandPaletteView(
            model: model,
            coordinator: coordinator,
            originController: originController,
            onDismiss: { [weak self] in self?.close() }
        )
        contentView = NSHostingView(rootView: view.environment(\.locale, locale))
    }

    func windowWillClose(_: Notification) {
        coordinator?.commandPaletteDidClose(self)
    }
}
