import AppKit
import TextFilters

/// One app command the command palette can invoke, distinct from a
/// discovered text filter (epic-14-implementation.md §5, §17 Slice 7). A
/// small, explicit, hand-maintained array — not generated from
/// `WorkspaceCommands` — per that section's accepted drift-risk tradeoff at
/// this list's current size. `@MainActor` because `action` manipulates the
/// (also `@MainActor`) `WindowCoordinator`.
///
/// `action`/`isAvailable` both take the palette's captured origin
/// `WindowController` (`nil` if the palette was opened with no document
/// window, or the origin has since closed) rather than resolving
/// `NSApp.keyWindow` themselves — the palette panel *is* the key window
/// while these run, so a command that resolved its own target internally
/// would silently act on the palette instead of the originating document
/// (post-review finding #7).
@MainActor
struct AppPaletteCommand: Identifiable {
    let id: String
    let title: String
    let isAvailable: (WindowCoordinator, WindowController?) -> Bool
    let action: (WindowCoordinator, WindowController?) -> Void

    init(
        id: String,
        title: String,
        isAvailable: @escaping (WindowCoordinator, WindowController?) -> Bool = { _, _ in true },
        action: @escaping (WindowCoordinator, WindowController?) -> Void
    ) {
        self.id = id
        self.title = title
        self.isAvailable = isAvailable
        self.action = action
    }
}

extension AppPaletteCommand {
    static let standard: [AppPaletteCommand] = [
        AppPaletteCommand(
            id: "newFile",
            title: String(localized: "New File"),
            // Mirrors `WorkspaceCommands`' real "New File" menu item: only
            // meaningful with an open folder (post-review finding #8 — the
            // palette previously aliased this to "New Tab", which drifted
            // from the real command it claimed to mirror in the same PR
            // that introduced it).
            isAvailable: { _, controller in controller?.fileTreeModel.root != nil },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.createInFolder(isDirectory: false, controller: controller)
            }
        ),
        // `isAvailable: controller != nil` on these three (third-adversarial
        // -pass finding #6): the palette can open with no document window
        // at all as its origin (e.g. invoked while a non-document window
        // is key), and every one of these otherwise falls back to
        // resolving its target from `NSApp.keyWindow` deeper in its own
        // async chain when given a `nil` explicit target — which, by the
        // time that `await` resumes, is the palette panel itself. Hiding
        // the row is the deliberate no-origin policy: never let one of
        // these silently target the palette/settings panel as a document
        // window or tab host.
        AppPaletteCommand(
            id: "newTab",
            title: String(localized: "New Tab"),
            isAvailable: { _, controller in controller != nil },
            action: { coordinator, controller in
                coordinator.newDocument(addAsTab: true, relativeTo: controller?.window)
            }
        ),
        // `relativeTo`/`in`: explicit target, not `NSApp.keyWindow` (which
        // is the palette itself while these run) — post-review finding #4.
        AppPaletteCommand(
            id: "open",
            title: String(localized: "Open…"),
            isAvailable: { _, controller in controller != nil },
            action: { coordinator, controller in
                coordinator.openFile(relativeTo: controller)
            }
        ),
        AppPaletteCommand(
            id: "openWithEncoding",
            title: String(localized: "Open with Encoding…"),
            isAvailable: { _, controller in controller != nil },
            action: { coordinator, controller in
                coordinator.openFileWithEncoding(relativeTo: controller)
            }
        ),
        AppPaletteCommand(
            id: "openFolder",
            title: String(localized: "Open Folder…"),
            isAvailable: { _, controller in controller != nil },
            action: { coordinator, controller in
                coordinator.chooseFolder(relativeTo: controller)
            }
        ),
        AppPaletteCommand(
            id: "save",
            title: String(localized: "Save"),
            isAvailable: { _, controller in controller?.model.canSave == true },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.saveDocument(in: controller)
            }
        ),
        AppPaletteCommand(
            id: "saveAs",
            title: String(localized: "Save As…"),
            isAvailable: { coordinator, controller in
                coordinator.isLiveController(controller) && controller?.model.hasActiveDocument == true
            },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.saveDocumentAs(in: controller)
            }
        ),
        AppPaletteCommand(
            id: "closeTab",
            title: String(localized: "Close Tab"),
            isAvailable: { _, controller in controller?.model.canClose == true },
            action: { coordinator, controller in
                guard let controller else { return }
                coordinator.closeTab(in: controller)
            }
        ),
        AppPaletteCommand(
            id: "toggleSidebar",
            title: String(localized: "Toggle Sidebar"),
            // Unlike the other commands above, toggling the sidebar has no
            // other precondition of its own to fall back on — without this,
            // it would stay "available" (and invocable) against an origin
            // whose window has already closed (post-review finding #5).
            isAvailable: { coordinator, controller in coordinator.isLiveController(controller) },
            action: { _, controller in controller?.model.sidebarVisible.toggle() }
        ),
        AppPaletteCommand(
            id: "insertSnippet",
            title: String(localized: "Insert Snippet…"),
            isAvailable: { _, controller in controller?.model.hasActiveDocument == true },
            action: { coordinator, controller in coordinator.presentSnippetPicker(origin: controller) }
        ),
        AppPaletteCommand(
            id: "editSnippets",
            title: String(localized: "Edit Snippets…"),
            isAvailable: { coordinator, controller in coordinator.isLiveController(controller) },
            action: { coordinator, controller in coordinator.editSnippets(relativeTo: controller?.window) }
        ),
        AppPaletteCommand(id: "showCommandsFolder",
                          title: String(localized: "Show Commands Folder")) { coordinator, _ in
            let directory = coordinator.commandsDirectory
            _ = TextFilterCommandDiscovery.discoverCommands(in: directory)
            NSWorkspace.shared.open(directory)
        },
    ]
}
