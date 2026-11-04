import AppKit
import CoreTransferable
import FileTree
import OutlineUI
import SwiftUI
import UniformTypeIdentifiers
import Workspace

extension SidebarView {
    @ViewBuilder
    var folderContent: some View {
        if fileTreeModel.root != nil {
            folderRootHeader
            folderFilterMenu
        }
        switch fileTreeModel.availability {
        case .noRoot:
            VStack(alignment: .leading) {
                Text("No folder opened").foregroundStyle(.secondary)
                Button("Open Folder…") { coordinator?.chooseFolder() }
                    .accessibilityIdentifier("openFolderButton")
                Text("⌘⇧O opens a folder").font(.caption).foregroundStyle(.secondary)
            }
            // `.contain`, not the default: without it this identifier leaks
            // down and overrides the button's own more-specific
            // `openFolderButton` identifier instead of just labeling this
            // VStack — confirmed via a real accessibility-tree dump. `.contain`
            // (unlike `.combine`) keeps the button independently clickable.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("folderSection")
        case .loading:
            ProgressView("Loading folder…")
        case let .rootUnreadable(reason):
            VStack(alignment: .leading) {
                Text(verbatim: reason).foregroundStyle(.secondary)
                Button("Choose Another Folder…") { coordinator?.chooseFolder() }
                    .accessibilityIdentifier("openFolderButton")
            }
        case .empty:
            VStack(alignment: .leading) {
                Text("Empty folder").foregroundStyle(.secondary)
                folderCreationActions
            }
        case .emptyAfterFilter:
            VStack(alignment: .leading) {
                Text("No matching files").foregroundStyle(.secondary)
                Button("Clear Filters") { fileTreeModel.preferences.filter = FileTreeFilter() }
            }
        case .ready:
            ForEach(fileTreeModel.rows) { row in
                FileTreeRowView(
                    row: row,
                    model: fileTreeModel,
                    isRenaming: fileTreeModel.renamingURL == row.entry.url,
                    opensOnSingleClick: fileTreeModel.preferences.opensOnSingleClick,
                    activate: activateFileTreeURL,
                    didRename: { old, new in
                        Task { await coordinator?.documentWasRenamed(from: old, to: new) }
                    }, didMove: { old, new in
                        Task { await coordinator?.documentWasRenamed(from: old, to: new) }
                    }, didDelete: { url in coordinator?.documentFileWasDeleted(at: url) }, didCreate: createdItem
                )
                .tag(SidebarSelection.file(row.id))
                // The row remains a discoverable accessibility container,
                // while an inline rename field keeps its own identifier for
                // keyboard and assistive-technology interaction.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("fileRow-\(row.entry.name)")
            }
        }
    }

    @ViewBuilder
    private var folderCreationActions: some View {
        if let root = fileTreeModel.root {
            Button("New File") { create(in: root, isDirectory: false) }
                .accessibilityIdentifier("newFileButton")
            Button("New Folder") { create(in: root, isDirectory: true) }
                .accessibilityIdentifier("newFolderButton")
        }
    }

    private var folderFilterMenu: some View {
        Menu("Folder Options") {
            Toggle("Show Hidden Files", isOn: filterBinding(\.showsHiddenFiles))
            Toggle("Supported Files Only", isOn: filterBinding(\.supportedFilesOnly))
            Toggle("Folders First", isOn: filterBinding(\.foldersFirst))
            Divider()
            Toggle("Open Files on Single Click", isOn: Binding(
                get: { fileTreeModel.preferences.opensOnSingleClick },
                set: { fileTreeModel.preferences.opensOnSingleClick = $0 }
            ))
        }
        .accessibilityIdentifier("folderOptionsButton")
    }

    private var folderRootHeader: some View {
        HStack {
            Label(fileTreeModel.root?.lastPathComponent ?? String(localized: "Folder"), systemImage: "folder")
                .lineLimit(1)
            Spacer()
            if let root = fileTreeModel.root {
                Menu {
                    Button("Open Another Folder…") { coordinator?.chooseFolder() }
                    Divider()
                    Button("New File") { create(in: root, isDirectory: false) }
                    Button("New Folder") { create(in: root, isDirectory: true) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Folder actions")
                .accessibilityIdentifier("folderActionsButton")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .dropDestination(for: URL.self) { urls, _ in
            guard let root = fileTreeModel.root else { return false }
            let context = fileTreeModel.beginOperation()
            Task {
                for url in urls {
                    do {
                        _ = try await fileTreeModel.copyExternal(url, intoDirectory: root, context: context)
                    } catch {
                        if fileTreeModel.isCurrent(context) {
                            fileTreeModel.recordOperationError(error)
                        }
                    }
                }
            }
            return !urls.isEmpty
        }
        .dropDestination(for: FileTreeInternalDrag.self) { items, _ in
            guard let root = fileTreeModel.root else { return false }
            let context = fileTreeModel.beginOperation()
            Task {
                for item in items {
                    guard let source = FileTreeInternalDrag.trustedURL(from: item, for: fileTreeModel) else {
                        if fileTreeModel.isCurrent(context) {
                            fileTreeModel
                                .recordOperationError(FileTreeOperationError.underlying("Untrusted folder move."))
                        }
                        continue
                    }
                    do {
                        let result = try await fileTreeModel.move(source, intoDirectory: root, context: context)
                        await coordinator?.documentWasRenamed(from: source, to: result.url)
                    } catch {
                        if fileTreeModel.isCurrent(context) {
                            fileTreeModel.recordOperationError(error)
                        }
                    }
                }
            }
            return !items.isEmpty
        }
        // Keep the root header discoverable without collapsing its action
        // menu into the header's accessibility identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folderRootHeader")
    }

    private func filterBinding(_ keyPath: WritableKeyPath<FileTreeFilter, Bool>) -> Binding<Bool> {
        Binding(
            get: { fileTreeModel.preferences.filter[keyPath: keyPath] },
            set: { value in
                var filter = fileTreeModel.preferences.filter
                filter[keyPath: keyPath] = value
                fileTreeModel.preferences.filter = filter
            }
        )
    }

    private func create(in directory: URL, isDirectory: Bool) {
        let context = fileTreeModel.beginOperation()
        Task {
            do {
                let result = try await (isDirectory
                    ? fileTreeModel.createFolder(in: directory, context: context)
                    : fileTreeModel.createFile(in: directory, context: context))
                if result.isCurrent {
                    createdItem(result.url, isDirectory, context: context)
                }
            } catch {
                if fileTreeModel.isCurrent(context) {
                    fileTreeModel.recordOperationError(error)
                }
            }
        }
    }

    private func createdItem(
        _ url: URL,
        _ isDirectory: Bool,
        context: FileTreeOperationContext
    ) {
        let originRoot = fileTreeModel.root
        let originAccessURL = fileTreeModel.rootAccessURL
        fileTreeModel.selectedURL = url
        if isDirectory {
            fileTreeModel.renamingURL = url
        } else {
            // The new document opens in its own native tab. Only that tab
            // should host the rename field; focus loss in this source tab
            // must not submit an unchanged "untitled.md" rename.
            fileTreeModel.renamingURL = nil
            guard let originWindow = coordinator?.controllers.first(where: { $0.model === model })?.window else {
                return
            }
            fileTreeModel.pendingOpenURL = url
            Task {
                await coordinator?.openDocument(
                    at: url,
                    folderRoot: originRoot,
                    folderAccessURL: originAccessURL,
                    folderSelectionURL: url,
                    folderRenameURL: url,
                    relativeTo: originWindow
                )
                if fileTreeModel.isCurrent(context), fileTreeModel.root == originRoot {
                    fileTreeModel.pendingOpenURL = nil
                }
            }
        }
    }
}
