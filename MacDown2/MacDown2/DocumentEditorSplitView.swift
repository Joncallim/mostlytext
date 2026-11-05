import AppKit
import AppSettings
import Contributions
import EditorCore
import FileCore
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Themes
import UniformTypeIdentifiers
import WebKit
import Workspace

// MARK: - Source / preview split

struct DocumentEditorSplitView: View {
    let model: WorkspaceModel
    let document: FileCore.FileDocument
    let tab: WorkspaceTab
    let identity: String
    @Binding var text: String
    let editorStore: EditorTextSystemStore
    let findStore: EditorFindModelStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let scrollController: ScrollSyncController
    let outlineController: OutlineController

    @Environment(\.windowCoordinator) var coordinator
    /// Not `private`: read by DocumentEditorSplitView+EditorPane.swift.
    @Environment(\.appSettings) var appSettings

    /// Not `private`: read by DocumentEditorSplitView+Divider.swift, split
    /// out to stay under the type-body-length lint budget (matches
    /// DocumentEditorSplitView+AppSettings.swift's same reason).
    @State var dragOriginFraction: Double?
    /// Drives `EditorStatusBarView`'s line/column and selection-count
    /// display. Updated by `EditorView`'s `onSelectionChange` callback — a
    /// dedicated `@State` because a caret move alone (no text edit) does not
    /// change `$text`, so nothing else in this view's body would otherwise
    /// trigger a re-render for it. Not `private`: read by
    /// DocumentEditorSplitView+EditorPane.swift.
    @State var statusBarSelection = NSRange(location: 0, length: 0)
    @State private var previewBlocks: [PreviewBlock]?
    @State var previewContributionSession = PreviewContributionSession()
    @State var previewDisplayCache = PreviewDisplayCache()
    @State var mathSession = MathPreviewSession()
    @State var mathDisplay: MathPreviewDisplay?

    /// Not `private`: read by DocumentEditorSplitView+EditorPane.swift.
    var parseSession: MarkdownParseSession {
        parseStore.session(for: identity)
    }

    var jsonSession: JSONAnalysisSession {
        jsonAnalysisStore.session(for: identity)
    }

    /// D7: gates the outline on format, not just its label — a Python or
    /// shell file's `# comment` lines are still parsed as Markdown headings
    /// by `parseSession`, and this is what keeps them out of the sidebar.
    private var isMarkdown: Bool {
        PreviewRouter.previewKind(for: document.format) == .markdown
    }

    /// D7/E11: the JSON outline channel is gated on the exact JSON format id,
    /// mirroring the Markdown gate above.
    private var isJSON: Bool {
        document.format.id == "json"
    }

    private var previewLayout: PreviewLayoutMode {
        tab.previewLayout ?? Self.defaultPreviewLayout(from: appSettings?.previewExport)
    }

    var currentSplitFraction: Double? {
        switch previewLayout {
        case let .split(fraction): fraction
        case .editorOnly, .previewOnly: nil
        }
    }

    /// Not `private`: read by DocumentEditorSplitView+EditorPane.swift.
    var editorConfiguration: EditorConfiguration {
        var config = EditorConfiguration.default
        if let editorSettings = appSettings?.editor {
            config.font = Self.resolvedFont(from: editorSettings.font)
            config.wrapsLines = editorSettings.wrapsLines
            config.showsInvisibles = editorSettings.showsInvisibles
        }
        config.scrollsPastEnd = false
        // EPIC-22 §6.11, Slice 4a: every format now gets a real, profile-
        // driven assist configuration — general mechanics (structural
        // pairing, Tab/Shift-Tab indent, Smart Home, Return-maintains-
        // indentation) for every format, Markdown's own additional behaviors
        // (list/blockquote continuation, symmetric delimiter pairing) only
        // for the exact Markdown format id. `WindowController` eagerly
        // creates a text system with `.default` (still `.disabled`) before
        // this format-specific configuration arrives, so a document can
        // never receive a transient assist configuration meant for a
        // different format.
        // The per-document Syntax Mode override (Slice 9d) governs editing
        // behaviour only; preview and outline gates keep using the file's
        // real `document.format`.
        let syntaxFormatID = tab.syntaxFormat.id
        let isMarkdown = syntaxFormatID == "markdown"
        config.editingAssists = Self.assistConfiguration(from: appSettings?.editor, isMarkdown: isMarkdown)
        config.languageProfile = LanguageEditingProfileRegistry.profile(for: syntaxFormatID)
        return config
    }

    var body: some View {
        splitContent
            .task(id: identity) {
                await loadInitialContent()
            }
            .onChange(of: SourceAnalysisText(text)) { _, source in
                mathSession.invalidate()
                mathDisplay = nil
                let newText = source.text
                // #35: only the format that can actually consume the result
                // pays for it. Before this gate, every keystroke in ANY
                // format (a Python file, a JSON file, plain text) built a
                // full swift-markdown AST/SourceMap AND ran a full JSON
                // analysis, discarding whichever (or both) outputs the
                // active format's preview/outline never reads — confirmed
                // by `previewPane`'s own switch (only `.markdown` reads
                // `parseSession`, only `.jsonOutline` reads `jsonSession`)
                // and `refreshOutline`/`refreshJSONOutline`'s existing
                // format gates, which already tolerate `document`/`result`
                // staying `nil` for a format they don't apply to.
                if isMarkdown {
                    parseSession.textDidChange(newText)
                }
                if isJSON {
                    jsonSession.textDidChange(newText)
                }
            }
            .task(id: mathTaskID) {
                await refreshMathAnalysis()
            }
            .task(id: mathPresentationTaskID) {
                await refreshMathPresentation()
            }
            .onDisappear {
                mathSession.invalidate()
                mathDisplay = nil
            }
            .onChange(of: tab.syntaxFormat.id) { _, _ in
                attachHighlighter()
            }
            .onChange(of: document.format.id) { _, _ in
                // Save As format transitions re-gate both outline channels so
                // a stale Markdown outline never survives a move to JSON (and
                // vice versa), and invalidate a persisted preview mode the new
                // format cannot display. A format that gains a parser must
                // also START its analysis: the text did not change, so nothing
                // else would (#183 F05).
                resetInvalidPreviewMode()
                Task { await loadInitialContent() }
            }
            .onChange(of: parseSession.document) { _, _ in
                refreshPreviewBlocks()
                refreshOutline()
            }
            .onChange(of: previewContributionSession.composition) { _, _ in
                refreshRenderedPreviewBlocks()
            }
            .task(id: contributionTaskID) {
                await refreshPreviewContributions()
                refreshRenderedPreviewBlocks()
            }
            .onChange(of: jsonSession.result) { _, _ in
                refreshJSONOutline()
            }
            .onChange(of: appSettings?.markdown) { _, newValue in
                // #35: `setOptions` reparses immediately (`textDidChange`
                // internally) — a Markdown-settings change must not trigger
                // a needless parse of a non-Markdown document's text.
                guard isMarkdown else { return }
                parseSession.setOptions(Self.markdownParseOptions(from: newValue))
            }
    }

    /// The editor/preview split. Split from `body` (and the observation
    /// modifiers kept in `body`) so the compiler can type-check each chain.
    private var splitContent: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if previewLayout.showsEditor {
                    editorPane
                        .frame(width: PreviewPaneWidths.editorWidth(in: geometry.size.width, layout: previewLayout))
                }

                if previewLayout.showsEditor, previewLayout.showsPreview {
                    divider(in: geometry)
                }

                if previewLayout.showsPreview {
                    previewPane
                        // `.contain` (not the default) matters here: without it,
                        // this identifier silently overrides every more-specific
                        // identifier `previewPane`'s own content sets further down
                        // (e.g. `noPreviewPane`, `htmlPreviewModeToggle`) — SwiftUI
                        // propagates an ancestor's `.accessibilityIdentifier` onto
                        // descendant AX elements that don't resolve to their own
                        // distinct accessibility element, and `.contain` is what
                        // stops that by making this wrapper a real element of its
                        // own rather than a transparent pass-through.
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("previewPane")
                        .frame(width: PreviewPaneWidths.previewWidth(in: geometry.size.width, layout: previewLayout))
                }
            }
        }
        .onChange(of: scrollController.targetSourceLine) { _, line in
            guard let line, let sourceMap = parseSession.document?.sourceMap else { return }
            let range = sourceMap.utf16Range(ofLines: line ... line)
            coordinator?.folderSearchNavigationDidChange()
            editorStore.existingSystem(for: identity)?.scrollToVisible(utf16Range: range)
            scrollController.targetSourceLine = nil
        }
        .onChange(of: outlineController.pendingJumpLineRange) { _, lineRange in
            guard let lineRange, let sourceMap = parseSession.document?.sourceMap else { return }
            let range = sourceMap.utf16Range(ofLines: lineRange)
            // Both sides are told the same source line directly, rather than
            // the editor deriving its target and the preview reading back
            // where the editor landed — see `ScrollSyncController.jump(toLine:)`
            // for why that round trip is fragile for a jump this large.
            scrollController.jump(toLine: lineRange.lowerBound)
            coordinator?.folderSearchNavigationDidChange()
            editorStore.existingSystem(for: identity)?.revealSelection(utf16Range: range, flash: true, animated: true)
            outlineController.pendingJumpLineRange = nil
        }
        .onChange(of: outlineController.pendingJSONJumpSourceRange) { _, sourceRange in
            guard let sourceRange else { return }
            let nsRange = NSRange(sourceRange)
            coordinator?.folderSearchNavigationDidChange()
            editorStore.existingSystem(for: identity)?.revealSelection(utf16Range: nsRange, flash: true, animated: true)
            outlineController.pendingJSONJumpSourceRange = nil
        }
    }

    /// Initial content load: parse both sessions immediately (bypassing the
    /// debounce) and refresh both outline channels. Split out of `.task(id:)`
    /// so the compiler can type-check the view body.
    private func loadInitialContent() async {
        // #35: mirrors the exact-source change gate above — a non-Markdown,
        // non-JSON document (or a JSON document, for the Markdown side, and
        // vice versa) never reaches either parser, on open or on any later
        // edit.
        if isMarkdown {
            parseSession.setOptions(Self.markdownParseOptions(from: appSettings?.markdown))
            await parseSession.parseNow(text)
            refreshPreviewBlocks()
        }
        refreshOutline()
        if isJSON {
            await jsonSession.analyzeNow(text)
        }
        refreshJSONOutline()
    }

    private func refreshPreviewBlocks() {
        guard let document = parseSession.document, let text = parseSession.publishedText else {
            previewBlocks = nil
            previewDisplayCache.reset()
            return
        }
        previewBlocks = PreviewBlock.blocks(from: document, text: text)
        refreshRenderedPreviewBlocks()
    }

    private func refreshRenderedPreviewBlocks() {
        let displayed = previewContributionSession.displayedBlocks(
            baseBlocks: previewBlocks, currentRevision: parseSession.document?.revision
        )
        previewDisplayCache.update(revision: parseSession.document?.revision, blocks: displayed)
    }

    /// Keyed to document/tab identity + parsed revision only — never save
    /// state, dirty state, URL, or encoding — so a non-text `FileDocument`
    /// mutation neither restarts this task nor invalidates a valid composed
    /// TOC (architecture takeover, pass 1/10).
    private var contributionTaskID: PreviewContributionTaskID {
        PreviewContributionTaskID(
            documentIdentity: parseSession.identity, parsedRevision: parseSession.document?.revision
        )
    }

    private func refreshPreviewContributions() async {
        guard let document = parseSession.document, let text = parseSession.publishedText else { return }
        await previewContributionSession.refresh(
            taskID: contributionTaskID, document: document, text: text,
            baseBlocks: previewBlocks ?? PreviewBlock.blocks(from: document, text: text)
        )
    }

    /// D2: no parse of its own — a pure readout of the same `parseSession`
    /// the preview already reads.
    private func refreshOutline() {
        outlineController.update(
            document: parseSession.document,
            isMarkdown: isMarkdown,
            formatName: document.format.name,
            documentIdentity: parseSession.identity
        )
    }

    /// E11: a pure readout of the JSON analysis session. The format gate
    /// lives in the controller (`formatID == "json"`), so a Save As away
    /// from JSON clears the channel.
    private func refreshJSONOutline() {
        outlineController.updateJSON(
            result: jsonSession.result,
            formatID: document.format.id
        )
    }

    /// Save As invalidation: a persisted preview mode the new format cannot
    /// display is dropped (back to the format default) and the session is
    /// re-saved so the stale mode is not restored after relaunch.
    private func resetInvalidPreviewMode() {
        guard let mode = tab.previewMode, !PreviewRouter.supports(mode, for: document.format) else { return }
        model.tabStore.setPreviewMode(nil, for: tab.id)
        coordinator?.scheduleSaveSession()
    }
}
