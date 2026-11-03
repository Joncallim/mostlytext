import AppKit
import CoreTransferable
import FileTree
import OutlineUI
import SwiftUI
import UniformTypeIdentifiers
import Workspace

struct FileTreeRowView: View {
    let row: FileTreeRow
    let model: FileTreeModel
    let isRenaming: Bool
    let opensOnSingleClick: Bool
    let activate: (URL) -> Void
    let didRename: (URL, URL) -> Void
    let didMove: (URL, URL) -> Void
    let didDelete: (URL) -> Void
    let didCreate: (URL, Bool, FileTreeOperationContext) -> Void
    @State private var newName = ""
    @State private var renameSubmitted = false
    @State private var dragPayload: FileTreeInternalDrag?
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if row.entry.isDirectory, !row.entry.isPackage {
                Button { Task { await model.toggleExpansion(row.entry.url) } } label: {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 12, height: 12)
                }.buttonStyle(.plain)
                    .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
            } else {
                Color.clear.frame(width: 12, height: 12)
            }
            Image(systemName: row.entry.isDirectory
                ? (row.entry.isPackage ? "shippingbox" : "folder")
                : "doc.text")
                .foregroundStyle(row.entry.isDirectory ? .secondary : .primary)
                .frame(width: 16, height: 16)
            if isRenaming {
                TextField("Name", text: $newName, onCommit: commitRename)
                    .focused($renameFocused)
                    .accessibilityIdentifier("fileTreeRenameField")
                    .onAppear { newName = row.entry.name; renameFocused = true }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused {
                            commitRename()
                        }
                    }
                    .onExitCommand { model.renamingURL = nil }
            } else {
                Text(verbatim: row.entry.name).lineLimit(1)
            }
            if row.isLoading {
                ProgressView().controlSize(.small)
            }
            if let loadError = row.loadError {
                Button {
                    Task { await model.expand(row.entry.url) }
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
                .help("Could not load folder: \(loadError). Retry")
                .accessibilityLabel("Retry loading \(row.entry.name)")
            }
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: opensOnSingleClick ? 1 : 2).onEnded {
                if !row.entry.isDirectory || row.entry.isPackage {
                    activate(row.entry.url)
                }
            }
        )
        // `body` can be evaluated many times while a row is merely visible.
        // Issuing a trusted drag token there both mutates the registry and
        // leaves short-lived entries behind without the user ever dragging.
        // Cache one token for this displayed row instead; the fallback is
        // deliberately untrusted until the row appears.
        .draggable(dragPayload ?? FileTreeInternalDrag.untrustedPayload(for: row.entry.url))
        .onAppear(perform: refreshDragPayload)
        .onChange(of: row.entry.url) { _, _ in refreshDragPayload() }
        .onChange(of: model.root) { _, _ in refreshDragPayload() }
        .onDisappear {
            if let dragPayload {
                FileTreeInternalDrag.revoke(dragPayload)
            }
        }
        .dropDestination(for: FileTreeInternalDrag.self, action: { items, _ in
            guard !row.entry.isPackage else { return false }
            let destination = destinationDirectory
            let context = model.beginOperation()
            Task {
                for item in items where item.url != destination {
                    do {
                        guard let source = FileTreeInternalDrag.trustedURL(from: item, for: model) else {
                            if model.isCurrent(context) {
                                model.recordOperationError(FileTreeOperationError.underlying("Untrusted folder move."))
                            }
                            continue
                        }
                        let result = try await model.move(source, intoDirectory: destination, context: context)
                        didMove(source, result.url)
                    } catch {
                        if model.isCurrent(context) {
                            model.recordOperationError(error)
                        }
                    }
                }
            }
            return true
        })
        .dropDestination(for: URL.self, action: { urls, _ in
            guard !row.entry.isPackage else { return false }
            let destination = destinationDirectory
            let context = model.beginOperation()
            Task {
                for source in urls where source.standardizedFileURL != destination {
                    do {
                        _ = try await model.copyExternal(source, intoDirectory: destination, context: context)
                    } catch {
                        if model.isCurrent(context) {
                            model.recordOperationError(error)
                        }
                    }
                }
            }
            return !urls.isEmpty
        })
        .contextMenu {
            Button("New File") { create(in: destinationDirectory, isDirectory: false) }
                .accessibilityIdentifier("newFileButton")
            Button("New Folder") { create(in: destinationDirectory, isDirectory: true) }
                .accessibilityIdentifier("newFolderButton")
            Divider()
            Button("Rename") { model.renamingURL = row.entry.url }
                .accessibilityIdentifier("fileTreeRenameAction")
            Button("Duplicate") {
                let context = model.beginOperation()
                Task {
                    do {
                        _ = try await model.duplicate(row.entry.url, context: context)
                    } catch {
                        if model.isCurrent(context) {
                            model.recordOperationError(error)
                        }
                    }
                }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.entry.url]) }
            Divider()
            Button("Move to Trash", role: .destructive, action: requestMoveToTrash)
                .accessibilityIdentifier("fileTreeTrashAction")
        }
    }

    private var destinationDirectory: URL {
        (row.entry.isDirectory && !row.entry.isPackage) ? row.entry.url : row.entry.url.deletingLastPathComponent()
    }

    private func commitRename() {
        let old = row.entry.url
        guard model.renamingURL == old, !renameSubmitted else { return }
        if newName == row.entry.name {
            model.renamingURL = nil
            return
        }
        renameSubmitted = true
        let context = model.beginOperation()
        Task {
            defer { renameSubmitted = false }
            do {
                let result = try await model.rename(old, to: newName, context: context)
                didRename(old, result.url)
                if result.isCurrent {
                    model.renamingURL = nil
                }
            } catch {
                if model.isCurrent(context) {
                    model.recordOperationError(error)
                    model.renamingURL = nil
                }
            }
        }
    }

    private func create(in directory: URL, isDirectory: Bool) {
        let context = model.beginOperation()
        Task {
            do {
                let result = try await (isDirectory
                    ? model.createFolder(in: directory, context: context)
                    : model.createFile(in: directory, context: context))
                if result.isCurrent {
                    didCreate(result.url, isDirectory, context)
                }
            } catch {
                if model.isCurrent(context) {
                    model.recordOperationError(error)
                }
            }
        }
    }

    private func requestMoveToTrash() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let confirmation = FileTreeTrashConfirmation(model: model, source: row.entry.url) { [weak window] in
            window?.isVisible == true
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Move \"\(row.entry.name)\" to Trash?")
        alert.informativeText = String(localized: "You can recover it from the Trash in Finder.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                do {
                    guard let result = try await confirmation.run() else { return }
                    didDelete(result.url)
                } catch {
                    if confirmation.isCurrent {
                        model.recordOperationError(error)
                    }
                }
            }
        }
    }

    private func refreshDragPayload() {
        if let dragPayload {
            FileTreeInternalDrag.revoke(dragPayload)
        }
        dragPayload = FileTreeInternalDrag.issue(url: row.entry.url, from: model)
    }
}

struct FileTreeInternalDrag: Codable, Transferable {
    let url: URL
    private let token: UUID

    @MainActor
    static func issue(url: URL, from model: FileTreeModel) -> Self {
        FileTreeDragRegistry.shared.removeExpiredEntries()
        let token = UUID()
        FileTreeDragRegistry.shared.entries[token] = .init(
            modelID: ObjectIdentifier(model), root: model.root, source: url.standardizedFileURL, issuedAt: .now
        )
        return Self(url: url.standardizedFileURL, token: token)
    }

    /// A body-safe payload used before `onAppear` has issued the row's real
    /// in-process token. It can never pass `trustedURL`, so it cannot turn an
    /// evaluation-time placeholder into an internal move.
    static func untrustedPayload(for url: URL) -> Self {
        Self(url: url.standardizedFileURL, token: UUID())
    }

    @MainActor
    static func revoke(_ item: Self) {
        FileTreeDragRegistry.shared.entries.removeValue(forKey: item.token)
    }

    @MainActor
    static func trustedURL(from item: Self, for model: FileTreeModel) -> URL? {
        FileTreeDragRegistry.shared.removeExpiredEntries()
        // Not consumed: the row keeps one cached token for as long as it is displayed, so consuming it made the
        // first failed drop (a name collision, say) disable every later drag of that row. A replayed token still
        // has to match the model, root and source and name a node that currently exists.
        guard let entry = FileTreeDragRegistry.shared.entries[item.token],
              entry.modelID == ObjectIdentifier(model), entry.root == model.root,
              entry.source == item.url.standardizedFileURL,
              model.containsCurrentNode(entry.source) else { return nil }
        return entry.source
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .macDownFileTreeItem)
    }
}

@MainActor
private final class FileTreeDragRegistry {
    struct Entry {
        let modelID: ObjectIdentifier
        let root: URL?
        let source: URL
        let issuedAt: Date
    }

    static let shared = FileTreeDragRegistry()
    var entries: [UUID: Entry] = [:]

    /// A row issues its token when it appears and revokes it when it disappears, so the lifetime here is only a
    /// backstop for rows that never disappear cleanly. It must be long: at 30 s, a row idle for half a minute could
    /// no longer start an internal move ("Untrusted folder move").
    static let lifetime: TimeInterval = 8 * 60 * 60
    static let maximumEntries = 2000

    func removeExpiredEntries(now: Date = .now) {
        entries = entries.filter { now.timeIntervalSince($0.value.issuedAt) < Self.lifetime }
        if entries.count > Self.maximumEntries {
            let newest = entries.sorted { $0.value.issuedAt > $1.value.issuedAt }.prefix(Self.maximumEntries)
            entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
    }
}

extension UTType {
    static let macDownFileTreeItem = UTType(exportedAs: "com.joncallim.macdown2.file-tree-item")
}
