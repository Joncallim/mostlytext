import AppKit
import EditorCore
import FileCore

// MARK: - Insert / Edit Snippets (EPIC-22 §6.18, Slice 9e)

extension WindowCoordinator {
    /// The snippets offered for `formatID`: the built-ins plus the user's
    /// `snippets.json`, scoped and sorted by `SnippetCatalog`. A missing,
    /// unreadable or newer-version file contributes no user snippets and is
    /// never rewritten by this path.
    func availableSnippets(formatID: String, store: SnippetStore? = nil) -> [Snippet] {
        SnippetCatalog.snippets(user: (store ?? snippetStore).load().snippets, formatID: formatID)
    }

    /// A one-line explanation when the user's snippet file could not be used
    /// in full, so a bad file is never a silent "built-ins only".
    static func snippetNotice(for result: SnippetLoadResult) -> String? {
        switch result {
        case .missing:
            nil
        case let .loaded(library):
            library.skippedCount > 0
                ? String(localized: "\(library.skippedCount) entries in snippets.json were skipped.")
                : nil
        case .unreadable:
            String(localized: "snippets.json could not be read; showing built-in snippets only.")
        case .unsupportedVersion:
            String(localized: "snippets.json is from a newer version; showing built-in snippets only.")
        }
    }

    /// Shows the snippet picker for the key window's active document, or
    /// closes it if already open.
    func toggleInsertSnippet() {
        if let existing = snippetPanel {
            existing.close()
            return
        }
        presentSnippetPicker(origin: controllers.first { $0.window == NSApp.keyWindow })
    }

    /// `origin` is captured by the caller before any panel becomes key (the
    /// command palette passes its own captured origin): the picker and the
    /// eventual insert both target it, never `NSApp.keyWindow`.
    func presentSnippetPicker(origin: WindowController?) {
        guard snippetPanel == nil,
              let origin,
              let activeTab = origin.model.tabStore.activeTab,
              origin.editorStore.existingSystem(for: activeTab.id.uuidString) != nil
        else { return }

        let loaded = snippetStore.load()
        let snippets = SnippetCatalog.snippets(user: loaded.snippets, formatID: activeTab.syntaxFormat.id)
        let created = SnippetPickerPanel(
            coordinator: self,
            originController: origin,
            snippets: snippets,
            notice: Self.snippetNotice(for: loaded)
        )
        snippetPanel = created

        if let originWindow = origin.window {
            created.setFrameOrigin(NSPoint(
                x: originWindow.frame.midX - created.frame.width / 2,
                y: min(originWindow.frame.maxY - 120, originWindow.frame.midY + 150)
            ))
        } else {
            created.center()
        }
        // Deferred activation with an identity re-check — see
        // `toggleCommandPalette` for why.
        DispatchQueue.main.async { [weak self] in
            guard let self, snippetPanel === created else { return }
            NSApp.activate(ignoringOtherApps: true)
            created.makeKeyAndOrderFront(nil)
            created.orderFrontRegardless()
        }
    }

    func snippetPickerDidClose(_ panel: SnippetPickerPanel) {
        guard snippetPanel === panel else { return }
        snippetPanel = nil
    }

    /// Expands `snippet` at every selection of `controller`'s active editor as
    /// one undoable edit. The document's own dominant line ending is the
    /// fallback for a snippet inserted into text with no line break to copy.
    @discardableResult
    func insertSnippet(_ snippet: Snippet, into controller: WindowController, expectingTab: UUID? = nil) -> Bool {
        guard let activeTab = controller.model.tabStore.activeTab,
              expectingTab == nil || activeTab.id == expectingTab,
              let system = controller.editorStore.existingSystem(for: activeTab.id.uuidString),
              !system.isDetachedFromEditorView
        else { return false }
        let clipboard = NSPasteboard.general.string(forType: .string)
        let lineEnding = LineEndingProfile(detecting: system.textView.string).dominantEnding ?? .lineFeed
        let inserted = system.insertSnippet(
            SnippetTemplate(parsing: snippet.body),
            clipboard: clipboard,
            defaultLineEnding: lineEnding
        )
        if inserted {
            controller.window?.makeFirstResponder(system.textView)
        }
        return inserted
    }

    /// Opens `snippets.json` for editing, creating it (empty library) first
    /// if it does not exist. An existing — even unreadable — file is opened
    /// as is, never replaced.
    func editSnippets(relativeTo window: NSWindow?) {
        let store = snippetStore
        guard store.createIfMissing() else {
            NSSound.beep()
            return
        }
        Task { await openDocument(at: store.fileURL, relativeTo: window) }
    }
}
