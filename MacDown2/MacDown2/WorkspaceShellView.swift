import AppKit
import AppSettings
import EditorCore
import FileTree
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import SwiftUI
import Themes
import Workspace

/// The content of a single MostlyText document window.
///
/// With native window tabbing, each tab/window hosts its own `WorkspaceModel`
/// showing one document. The tab bar itself is provided by AppKit; this view
/// only renders the sidebar and content area for the document assigned to the
/// window.
struct WorkspaceShellView: View {
    @State private var model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    let findStore: EditorFindModelStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let outlineController: OutlineController
    let fileTreeModel: FileTreeModel
    let folderSearchModel: FolderSearchModel
    let externalFileController: ExternalFileController

    @Environment(\.appSettings) private var appSettings

    init(
        model: WorkspaceModel,
        editorStore: EditorTextSystemStore,
        findStore: EditorFindModelStore,
        highlightStore: SyntaxHighlightStore,
        parseStore: MarkdownParseStore,
        jsonAnalysisStore: JSONAnalysisStore,
        themeController: ThemeController,
        outlineController: OutlineController,
        fileTreeModel: FileTreeModel,
        folderSearchModel: FolderSearchModel,
        externalFileController: ExternalFileController
    ) {
        _model = State(initialValue: model)
        self.editorStore = editorStore
        self.findStore = findStore
        self.highlightStore = highlightStore
        self.parseStore = parseStore
        self.jsonAnalysisStore = jsonAnalysisStore
        self.themeController = themeController
        self.outlineController = outlineController
        self.fileTreeModel = fileTreeModel
        self.folderSearchModel = folderSearchModel
        self.externalFileController = externalFileController
    }

    private var activePreviewLayout: PreviewLayoutMode {
        model.tabStore.activeTab?.previewLayout
            ?? DocumentEditorSplitView.defaultPreviewLayout(from: appSettings?.previewExport)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
            SidebarView(
                model: model,
                outlineController: outlineController,
                fileTreeModel: fileTreeModel,
                folderSearchModel: folderSearchModel
            )
        } detail: {
            ContentAreaView(
                model: model,
                editorStore: editorStore,
                findStore: findStore,
                highlightStore: highlightStore,
                parseStore: parseStore,
                jsonAnalysisStore: jsonAnalysisStore,
                themeController: themeController,
                outlineController: outlineController,
                externalFileController: externalFileController
            )
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.previewLayout, activePreviewLayout)
        .task(id: themeController.current) {
            highlightStore.applyThemeToAll(themeController.current)
        }
        .task(id: appSettings?.editor.font) {
            guard let appSettings else { return }
            highlightStore.applyFontToAll(DocumentEditorSplitView.resolvedFont(from: appSettings.editor.font))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.sidebarVisible.toggle()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
        }
    }

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { model.sidebarVisible ? .all : .detailOnly },
            set: { newValue in
                model.sidebarVisible = newValue != .detailOnly
            }
        )
    }
}
