/// Where one real menu command stands relative to the command palette
/// (EPIC-22 §6, issue #117 item 4). `WorkspaceCommands` is a SwiftUI
/// `Commands` value and cannot be enumerated at runtime, so this is a
/// hand-written catalog that names every literal-titled menu item once;
/// `CommandRegistryConsistency` (exercised by `CommandRegistryConsistencyTests`,
/// which scans the `Commands` sources for their literal titles) fails when a
/// menu item is added, renamed, or removed without updating it, or when a
/// palette entry and its catalog record disagree.
struct CommandDescriptor: Equatable {
    enum Exclusion: String, Equatable {
        /// A submenu or menu header; its children are catalogued on their own.
        case menuContainer
        /// A member of a menu populated at runtime (tabs, recents, headings).
        case dynamicItems
        case debugOnly
        /// The command that opens the palette itself.
        case paletteItself
        /// App information and license readers remain in the application menu.
        case informational
        /// Reauthorization is scoped to unavailable recent items; the palette
        /// already offers the ordinary Open File and Open Folder commands.
        case recentReauthorization
        /// Palette-eligible in principle, but not yet wired: doing so needs
        /// explicit origin-window capture (the palette is the key window
        /// while a command runs). Carried forward in the EPIC-22 tracker.
        case notYetWired
    }

    enum Disposition: Equatable {
        case palette(id: String)
        case excluded(Exclusion)
    }

    /// The literal exactly as it appears in the `Commands` source, so a
    /// title interpolating a value keeps its `\(…)` text.
    let menuTitle: String
    let disposition: Disposition

    init(_ menuTitle: String, _ disposition: Disposition) {
        self.menuTitle = menuTitle
        self.disposition = disposition
    }
}

extension CommandDescriptor {
    static let catalog: [CommandDescriptor] = [
        CommandDescriptor("New File", .palette(id: "newFile")),
        CommandDescriptor("New Folder", .excluded(.notYetWired)),
        CommandDescriptor("New Tab", .palette(id: "newTab")),
        CommandDescriptor("Open…", .palette(id: "open")),
        CommandDescriptor("Open with Encoding…", .palette(id: "openWithEncoding")),
        CommandDescriptor("Open Folder…", .palette(id: "openFolder")),
        CommandDescriptor("Open Recent Folder", .excluded(.menuContainer)),
        CommandDescriptor("Open Recent File", .excluded(.menuContainer)),
        CommandDescriptor("Clear Menu", .excluded(.dynamicItems)),
        CommandDescriptor("Choose a File Again…", .excluded(.recentReauthorization)),
        CommandDescriptor("Choose a Folder Again…", .excluded(.recentReauthorization)),
        CommandDescriptor("Quick Open…", .excluded(.notYetWired)),
        CommandDescriptor("Save", .palette(id: "save")),
        CommandDescriptor("Save As…", .palette(id: "saveAs")),
        CommandDescriptor("Close Tab", .palette(id: "closeTab")),
        CommandDescriptor("Export…", .excluded(.notYetWired)),
        CommandDescriptor("Folder", .excluded(.menuContainer)),
        CommandDescriptor("Rename", .excluded(.notYetWired)),
        CommandDescriptor("Duplicate", .excluded(.notYetWired)),
        CommandDescriptor("Move to Trash", .excluded(.notYetWired)),
        CommandDescriptor("Show Next Tab", .excluded(.notYetWired)),
        CommandDescriptor("Show Previous Tab", .excluded(.notYetWired)),
        CommandDescriptor("Select Tab \\(index)", .excluded(.dynamicItems)),
        CommandDescriptor("Layout", .excluded(.menuContainer)),
        CommandDescriptor("Theme", .excluded(.menuContainer)),
        CommandDescriptor("Toggle Sidebar", .palette(id: "toggleSidebar")),
        CommandDescriptor("Focus Outline", .excluded(.notYetWired)),
        CommandDescriptor("Reveal Active File", .excluded(.notYetWired)),
        CommandDescriptor("Go to Line/Column…", .excluded(.notYetWired)),
        CommandDescriptor("Find…", .excluded(.notYetWired)),
        CommandDescriptor("About MostlyText", .excluded(.informational)),
        CommandDescriptor("Open Source Licenses…", .excluded(.informational)),
        CommandDescriptor("Debug", .excluded(.debugOnly)),
        CommandDescriptor("Mark Active Tab Dirty", .excluded(.debugOnly)),
        CommandDescriptor("Reopen with Encoding", .excluded(.menuContainer)),
        CommandDescriptor("Save with Encoding", .excluded(.menuContainer)),
        CommandDescriptor("Other", .excluded(.menuContainer)),
        CommandDescriptor("Lines", .excluded(.menuContainer)),
        CommandDescriptor("Convert Case", .excluded(.menuContainer)),
        CommandDescriptor("Convert Line Endings", .excluded(.menuContainer)),
        CommandDescriptor("Heading", .excluded(.menuContainer)),
        CommandDescriptor("Heading \\(level)", .excluded(.dynamicItems)),
        CommandDescriptor("Duplicate Line", .excluded(.notYetWired)),
        CommandDescriptor("Delete Line", .excluded(.notYetWired)),
        CommandDescriptor("Move Line Up", .excluded(.notYetWired)),
        CommandDescriptor("Move Line Down", .excluded(.notYetWired)),
        CommandDescriptor("Join Lines", .excluded(.notYetWired)),
        CommandDescriptor("Sort Lines", .excluded(.notYetWired)),
        CommandDescriptor("Remove Duplicate Lines", .excluded(.notYetWired)),
        CommandDescriptor("Trim Trailing Whitespace", .excluded(.notYetWired)),
        CommandDescriptor("Uppercase", .excluded(.notYetWired)),
        CommandDescriptor("Lowercase", .excluded(.notYetWired)),
        CommandDescriptor("Capitalize", .excluded(.notYetWired)),
        CommandDescriptor("Increase Indent", .excluded(.notYetWired)),
        CommandDescriptor("Decrease Indent", .excluded(.notYetWired)),
        CommandDescriptor("Toggle Comment", .excluded(.notYetWired)),
        CommandDescriptor("Bold", .excluded(.notYetWired)),
        CommandDescriptor("Italic", .excluded(.notYetWired)),
        CommandDescriptor("Inline Code", .excluded(.notYetWired)),
        CommandDescriptor("Paragraph", .excluded(.notYetWired)),
        CommandDescriptor("Format JSON", .excluded(.notYetWired)),
        CommandDescriptor("Format JSON with Sorted Keys", .excluded(.notYetWired)),
        CommandDescriptor("Add Cursor Above", .excluded(.notYetWired)),
        CommandDescriptor("Add Cursor Below", .excluded(.notYetWired)),
        CommandDescriptor("Select Next Occurrence", .excluded(.notYetWired)),
        CommandDescriptor("Select All Occurrences", .excluded(.notYetWired)),
        CommandDescriptor("Snippets", .excluded(.menuContainer)),
        CommandDescriptor("Insert Snippet…", .palette(id: "insertSnippet")),
        CommandDescriptor("Edit Snippets…", .palette(id: "editSnippets")),
        CommandDescriptor("Commands", .excluded(.menuContainer)),
        CommandDescriptor("Command Palette…", .excluded(.paletteItself)),
        CommandDescriptor("Show Commands Folder", .palette(id: "showCommandsFolder")),
        CommandDescriptor("Add Example Scripts", .excluded(.notYetWired)),
    ]
}
