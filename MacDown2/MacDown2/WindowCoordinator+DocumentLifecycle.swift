import AppKit

/// Close/Save/Save As, in both their real-menu ("key window") and
/// explicit-target forms. Split out of `WindowCoordinator.swift`'s main
/// class body to stay under the `type_body_length`/`file_length` lint
/// budgets, matching `WindowCoordinator+SessionRestore.swift`'s same
/// reason.
///
/// The explicit-target variants exist for the command palette
/// (post-review finding #7 on the E14B remediation): the palette panel
/// itself is `NSApp.keyWindow` while these run, so a command that resolved
/// its own target from `NSApp.keyWindow` at invocation time would silently
/// act on the palette instead of the document window the user actually
/// meant. The real menu commands are unchanged thin wrappers that resolve
/// the key window once and delegate to the same body.
extension WindowCoordinator {
    var canSaveCurrentDocument: Bool {
        _ = commandStateRevision
        return currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)?.model.canSave == true
    }

    var canSaveAsCurrentDocument: Bool {
        _ = commandStateRevision
        return currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)?
            .model.hasActiveDocument == true
    }

    /// Closes the tab/window that is currently key.
    func closeKeyWindow() {
        guard let controller = controllers.first(where: { $0.window?.isKeyWindow ?? false }) else {
            // Settings, About, the welcome window: ⌘W closes them like any other Mac window.
            if Self.isCloseableNonDocumentWindow(NSApp.keyWindow) {
                NSApp.keyWindow?.performClose(nil)
            }
            return
        }
        closeTab(in: controller)
    }

    /// Whether ⌘W applies: a document window with a closable tab, or any other closable key window.
    var canCloseKeyWindow: Bool {
        _ = commandStateRevision
        if let keyModel {
            return keyModel.canClose
        }
        return Self.isCloseableNonDocumentWindow(NSApp.keyWindow)
    }

    static func isCloseableNonDocumentWindow(_ window: NSWindow?) -> Bool {
        window?.styleMask.contains(.closable) == true
    }

    func closeTab(in controller: WindowController) {
        guard let window = controller.window else { return }
        // Call windowShouldClose directly instead of NSWindow.performClose. Under
        // native tabbing, performClose can trigger tab-group selection changes even
        // when windowShouldClose returns false (dirty document), causing a sibling
        // tab to erroneously become key after the sheet is dismissed.
        if controller.windowShouldClose(window) {
            controller.close()
        }
    }

    func saveKeyDocument() {
        guard let controller = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)
        else { return }
        saveDocument(in: controller)
    }

    func saveKeyDocumentAs() {
        guard let controller = currentCommandController(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow)
        else { return }
        saveDocumentAs(in: controller)
    }

    /// Uses `saveDocumentFromExplicitOrigin()`, not the plain
    /// `saveDocument()`, so a destination panel — needed whenever the
    /// active document is untitled or its backing file has become
    /// unavailable — is always bound to `controller`'s own window
    /// explicitly. Correct for both the real Save menu item (where that
    /// window already is the key window) and the command palette (where,
    /// by the time this resolves, it may no longer be —
    /// third-adversarial-pass finding #5, mirroring `saveDocumentAs(in:)`
    /// just below).
    func saveDocument(in controller: WindowController) {
        Task { await controller.saveDocumentFromExplicitOrigin() }
    }

    /// Uses `saveDocumentAsFromExplicitOrigin()`, not the plain
    /// `saveDocumentAs()`, so the destination panel is always bound to
    /// `controller`'s own window explicitly — correct for both the real
    /// Save As menu item (where that window already is the key window) and
    /// the command palette (where, by the time this resolves, it may no
    /// longer be — post-review finding #4).
    func saveDocumentAs(in controller: WindowController) {
        guard let document = controller.model.activeDocument,
              let admission = controller.model.reserveSaveAs(for: document) else { return }
        Task {
            await controller.saveDocumentAsFromExplicitOrigin(expecting: document, admission: admission)
        }
    }
}
