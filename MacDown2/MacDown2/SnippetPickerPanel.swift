import AppKit
import EditorCore
import SwiftUI

/// A floating panel hosting `SnippetPickerView` (EPIC-22 §6.18, Slice 9e).
/// Ownership mirrors `QuickOpenPanel`: `WindowCoordinator.snippetPanel` holds
/// it strongly while open and releases it via `snippetPickerDidClose`.
@MainActor
final class SnippetPickerPanel: NSPanel, NSWindowDelegate {
    private weak var coordinator: WindowCoordinator?
    /// The window the picker was opened from, so the coordinator can close it
    /// the instant that window closes (and the insert targets it, never the
    /// panel itself, which is the key window while it is on screen).
    private(set) weak var originController: WindowController?
    private var originCloseObserver: (any NSObjectProtocol)?

    convenience init(
        coordinator: WindowCoordinator,
        originController: WindowController,
        snippets: [Snippet],
        notice: String? = nil,
        locale: Locale
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

        // The tab the list was scoped to; the insert refuses a different one.
        let scopedTabID = originController.model.tabStore.activeTab?.id
        let view = SnippetPickerView(
            model: SnippetPickerModel(snippets: snippets, notice: notice),
            onInsert: { [weak self, weak coordinator, weak originController] snippet in
                guard let coordinator, let originController else { return false }
                if originController.model.tabStore.activeTab?.id != scopedTabID {
                    // The list was scoped to another tab; never insert into this one.
                    NSSound.beep()
                    self?.close()
                    return false
                }
                guard coordinator.insertSnippet(snippet, into: originController, expectingTab: scopedTabID) else {
                    NSSound.beep()
                    return false
                }
                return true
            },
            onDismiss: { [weak self] in self?.close() }
        )
        contentView = NSHostingView(rootView: view.environment(\.locale, locale))
        // Self-contained origin-close handling: an orphaned picker would
        // target an evicted editor store.
        // A nil `object` would observe every window, so no window → no observer.
        guard let originWindow = originController.window else { return }
        originCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: originWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func windowWillClose(_: Notification) {
        if let originCloseObserver {
            NotificationCenter.default.removeObserver(originCloseObserver)
            self.originCloseObserver = nil
        }
        coordinator?.snippetPickerDidClose(self)
    }
}
