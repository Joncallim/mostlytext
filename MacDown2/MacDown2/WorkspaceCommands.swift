import AppKit
import AppSettings
import EditorCore
import SwiftUI
import Themes
import Workspace

struct WorkspaceCommands: Commands {
    // Internal, not `private`: `WorkspaceCommands+TextFormatting.swift`
    // reads it from an extension in a separate file, mirroring this
    // codebase's established per-file command-bridge extraction pattern
    // used once a type's own body grows past its line-count limit.
    @Environment(\.windowCoordinator) var coordinator
    @Environment(\.appSettings) private var appSettings
    @FocusedValue(\.previewLayout) private var previewLayout
    private let themeController: ThemeController

    init(themeController: ThemeController) {
        self.themeController = themeController
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") {
                coordinator?.newFileCommand()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                coordinator?.createInKeyFolder(isDirectory: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(coordinator?.keyFolderRoot == nil)

            Button("New Tab") {
                coordinator?.newDocument(addAsTab: true)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Open…") {
                coordinator?.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open with Encoding…") {
                coordinator?.openFileWithEncoding()
            }

            Button("Open Folder…") {
                coordinator?.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Menu("Open Recent Folder") {
                ForEach(coordinator?.recentFolderRoots.roots ?? [], id: \.self) { url in
                    Button(url.lastPathComponent) { coordinator?.openRecentFolder(url) }
                }
                Divider()
                Button("Clear Menu") { coordinator?.recentFolderRoots.clear() }
            }

            // EPIC-22 issue #112, Slice 6c. Unlike `RecentFolderRoots`
            // (whose stale-bookmark cleanup happens reactively inside
            // `resolve(_:)`, called constantly during ordinary folder
            // browsing), `RecentFileDocuments.pruneMissingFiles()` is called
            // from `record(_:)` and at launch (`reload()`) rather than from
            // this menu's own body — a SwiftUI `Commands` menu has no
            // reliable per-open lifecycle hook to run it from immediately
            // before display, and every real file open already routes
            // through `record(_:)` (see `openDocument(at:...)`'s own doc
            // comment), so a moved/deleted entry is pruned the next time the
            // user opens anything, not just when they happen to look at
            // this specific menu.
            Menu("Open Recent File") {
                ForEach(coordinator?.recentFileDocuments.documents ?? [], id: \.self) { url in
                    Button(url.lastPathComponent) { coordinator?.openRecentFile(url) }
                }
                Divider()
                Button("Clear Menu") { coordinator?.recentFileDocuments.clear() }
            }

            Divider()

            Button("Quick Open…") {
                coordinator?.toggleQuickOpen()
            }
            .keyboardShortcut("p", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                coordinator?.saveKeyDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(coordinator?.canSaveCurrentDocument != true)

            Button("Save As…") {
                coordinator?.saveKeyDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(coordinator?.canSaveAsCurrentDocument != true)

            encodingMenus

            Button("Close Tab") {
                coordinator?.closeKeyWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(coordinator?.canCloseKeyWindow != true)

            Divider()

            Button("Export…") {
                coordinator?.exportCoordinator.beginExportActiveDocument()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(coordinator?.exportCoordinator.canExportActiveDocument != true)

            #if ISSUE117_NATIVE_ACCEPTANCE
                Button("Validate Export… (#117 Test Build)") {
                    Issue117NativeAcceptance.run(from: coordinator)
                }
                .disabled(coordinator?.exportCoordinator.canExportActiveDocument != true)

                Button("Show #117 Acceptance Log") {
                    Issue117NativeAcceptance.showLog()
                }
            #endif
        }

        CommandMenu("Folder") {
            Button("Rename") {
                coordinator?.renameKeyFolderSelection()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(coordinator?.keyFolderSelection == nil)

            Button("Duplicate") {
                coordinator?.duplicateKeyFolderSelection()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(coordinator?.keyFolderSelection == nil)

            Button("Move to Trash", role: .destructive) {
                coordinator?.trashKeyFolderSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(coordinator?.keyFolderSelection == nil)
        }

        CommandGroup(before: .windowArrangement) {
            Button("Show Next Tab") {
                coordinator?.selectNextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(coordinator?.keyWindowHasMultipleTabs != true)

            Button("Show Previous Tab") {
                coordinator?.selectPreviousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(coordinator?.keyWindowHasMultipleTabs != true)

            ForEach(1 ..< 10, id: \.self) { index in
                Button("Select Tab \(index)") {
                    coordinator?.selectTab(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                .disabled(coordinator?.keyWindowHasTab(at: index - 1) != true)
            }
        }

        CommandGroup(before: .sidebar) {
            Menu("Layout") {
                let layout = previewLayout
                    ?? DocumentEditorSplitView.defaultPreviewLayout(from: appSettings?.previewExport)

                Button(
                    action: { setPreviewLayout(.editorOnly) },
                    label: {
                        if layout == .editorOnly {
                            Text("✓ Editor Only")
                        } else {
                            Text("    Editor Only")
                        }
                    }
                )
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button(
                    action: { setPreviewLayout(.split(fraction: 0.5)) },
                    label: {
                        if case .split = layout {
                            Text("✓ Split Editor & Preview")
                        } else {
                            Text("    Split Editor & Preview")
                        }
                    }
                )
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button(
                    action: { setPreviewLayout(.previewOnly) },
                    label: {
                        if layout == .previewOnly {
                            Text("✓ Preview Only")
                        } else {
                            Text("    Preview Only")
                        }
                    }
                )
                .keyboardShortcut("3", modifiers: [.command, .option])
            }

            Picker(
                "Appearance",
                selection: Binding(
                    get: { themeController.appearanceMode },
                    set: { themeController.setAppearanceMode($0) }
                )
            ) {
                Text("Follow System").tag(ThemeAppearanceMode.system)
                Text("Light").tag(ThemeAppearanceMode.light)
                Text("Dark").tag(ThemeAppearanceMode.dark)
            }

            Menu("Theme") {
                let active = themeController.current
                let lightThemes = themeController.available.filter { $0.appearance == .light }
                let darkThemes = themeController.available.filter { $0.appearance == .dark }

                Section("Light") {
                    ForEach(lightThemes) { theme in
                        Button(
                            action: { themeController.select(theme) },
                            label: {
                                // Theme names are proper nouns and are never translated.
                                Text(verbatim: (active.id == theme.id ? "✓ " : "    ") + theme.name)
                            }
                        )
                    }
                }

                Section("Dark") {
                    ForEach(darkThemes) { theme in
                        Button(
                            action: { themeController.select(theme) },
                            label: {
                                // Theme names are proper nouns and are never translated.
                                Text(verbatim: (active.id == theme.id ? "✓ " : "    ") + theme.name)
                            }
                        )
                    }
                }
            }

            Button("Toggle Sidebar") {
                coordinator?.keyModel?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            Button("Focus Outline") {
                coordinator?.focusOutline()
            }
            .keyboardShortcut("o", modifiers: [.control, .command])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)

            Button("Reveal Active File") {
                coordinator?.revealActiveFile()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .disabled(coordinator?.keyModel?.activeDocument?.fileURL == nil)

            Button("Go to Line/Column…") {
                coordinator?.toggleGoToLine()
            }
            .keyboardShortcut("g", modifiers: [.control])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)

            // EPIC-22 §6.14, Slice 5a: an inline docked bar, not a floating
            // panel, so this only toggles per-tab state — see
            // `WindowCoordinator+Find.swift`. Bound to the standard ⌘F (owner
            // decision, 2026-10-13: the Edit menu has no stock Find submenu, so
            // ⌘F previously did nothing in the editor); this replaces the
            // original Slice 5a ⌃F binding (a second, hidden ⌃F item does not
            // register its shortcut in a SwiftUI command).
            Button("Find in Document…") {
                coordinator?.toggleFind()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(coordinator?.keyModel?.hasActiveDocument != true)
        }

        textFormattingCommands
        lineTransformCommands
        snippetCommands

        #if DEBUG
            CommandMenu("Debug") {
                Button("Mark Active Tab Dirty") {
                    coordinator?.keyModel?.tabStore.updateActiveDocument { $0.updatingText($0.text + " ") }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift, .option])
                .disabled(coordinator?.keyModel?.hasActiveDocument != true)
            }
        #endif
    }

    private func setPreviewLayout(_ layout: PreviewLayoutMode) {
        coordinator?.setPreviewLayout(layout)
    }
}

// MARK: - Focused layout state

/// Key for the active tab's preview layout so `Commands` can reactively update
/// the Layout menu checkmark. The value is published from the key window's
/// shell view via `.focusedSceneValue`.
private struct PreviewLayoutFocusedValueKey: FocusedValueKey {
    typealias Value = PreviewLayoutMode
}

extension FocusedValues {
    var previewLayout: PreviewLayoutMode? {
        get { self[PreviewLayoutFocusedValueKey.self] }
        set { self[PreviewLayoutFocusedValueKey.self] = newValue }
    }
}
