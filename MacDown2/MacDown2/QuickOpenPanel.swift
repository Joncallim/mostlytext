import AppKit
import SwiftUI
import TextSearch

/// A borderless, floating panel hosting `QuickOpenView` (EPIC-22 §6.15,
/// Slice 6b) — Cmd-P fuzzy file navigation for the active folder root.
///
/// Ownership mirrors `CommandPalettePanel` exactly, per §6.15's own explicit
/// decision to reuse that idiom rather than `GoToLinePanel`'s: `NSPanel`'s
/// `isReleasedWhenClosed` defaults to `false`, so `WindowCoordinator`
/// (`quickOpen` in `WindowCoordinator+QuickOpen.swift`) holds this panel
/// strongly for exactly as long as it is open, releasing it via
/// `quickOpenDidClose` when `windowWillClose` fires. Only a `weak` reference
/// back to the coordinator, so there is no retain cycle.
@MainActor
final class QuickOpenPanel: NSPanel, NSWindowDelegate {
    private weak var coordinator: WindowCoordinator?
    /// The window this panel was opened from, so `WindowCoordinator` can
    /// close it the instant that window closes rather than leaving it open
    /// against an already-evicted `fileTreeModel`/`workspaceFileIndex` —
    /// same reasoning as `CommandPalettePanel.originController` and
    /// `GoToLinePanel.originController`.
    private(set) weak var originController: WindowController?
    private var submission: QuickOpenSubmission?

    convenience init(
        coordinator: WindowCoordinator,
        originController: WindowController,
        index: WorkspaceFileIndex
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

        // Issue #112, Slice 6c: "Recent-file history feeds Quick Open
        // ranking." Computed once here, from the origin's own root at the
        // moment Quick Open opens — see `QuickOpenModel.init`'s own doc
        // comment for why a live-updating signal isn't needed for a
        // short-lived filtering session.
        let recentRelativePaths = originController.fileTreeModel.rootAccessURL
            .map { coordinator.recentFileDocuments.relativePaths(under: $0) } ?? []
        let model = QuickOpenModel(index: index, recentRelativePaths: recentRelativePaths)
        let origin = Self.currentOrigin(for: originController)
        let actionGate = QuickOpenActionGate(index: index) { [weak originController] in
            Self.currentOrigin(for: originController)
        }
        let submission = QuickOpenSubmission(
            model: model,
            onOpen: { [weak self, weak coordinator, weak originController] result in
                guard self?.isVisible == true,
                      let coordinator, let originController, let origin,
                      model.selectedResult == result,
                      await actionGate.admit(result, from: origin),
                      self?.isVisible == true,
                      model.selectedResult == result,
                      let originWindow = originController.window
                else { return false }
                // Use the root that produced this row, after checking the
                // current request still owns it. The document-open path
                // rechecks through its own asynchronous load/rebuild steps.
                let url = origin.lexicalRoot.appendingPathComponent(result.path.relativePath)
                Task {
                    guard actionGate.isCurrent(origin) else { return }
                    // `relativeTo: originController.window`, not
                    // `NSApp.keyWindow` — this panel itself is the key
                    // window while it is on screen, exactly the mistake
                    // `CommandPalettePanel`'s own origin-capture idiom
                    // exists to avoid (post-review finding #7 there).
                    await coordinator.openDocument(
                        at: url,
                        folderRoot: origin.lexicalRoot,
                        folderAccessURL: origin.accessRoot,
                        relativeTo: originWindow,
                        shouldContinue: { actionGate.isCurrent(origin) },
                        useAmbientWindow: false
                    )
                }
                return true
            },
            onDismiss: { [weak self] in self?.close() }
        )
        self.submission = submission
        let view = QuickOpenView(model: model, submission: submission, onDismiss: { [weak self] in self?.close() })
        contentView = NSHostingView(rootView: view)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) {
            // A filtered List can own focus even while the search field still
            // displays the query. Return is the panel's default file action.
            submission?.submit()
            return
        }
        super.sendEvent(event)
    }

    func windowWillClose(_: Notification) {
        coordinator?.quickOpenDidClose(self)
    }

    private static func currentOrigin(for controller: WindowController?) -> QuickOpenOrigin? {
        controller?.currentQuickOpenOrigin
    }
}
