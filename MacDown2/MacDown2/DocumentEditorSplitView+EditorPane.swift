import EditorCore
import FileCore
import Highlighting
import SwiftUI

/// The editor pane and its status bar (epic-22-implementation.md §6.7, §17
/// Slice 2b). Split out of `DocumentEditorSplitView.swift` to stay under the
/// type-body-length/file-length lint budgets, matching
/// `DocumentEditorSplitView+Divider.swift`'s same reason — `editorConfiguration`,
/// `parseSession`, `appSettings`, and `statusBarSelection` are internal (not
/// `private`) in the main file for that reason.
extension DocumentEditorSplitView {
    var editorPane: some View {
        VStack(spacing: 0) {
            // EPIC-22 §6.14, Slice 5a: an inline docked bar, not a floating
            // panel — see `FindBarView`'s own doc comment. Reading the
            // model via `findStore.existingModel(for:)` rather than always
            // calling `findStore.model(for:)` means a tab that has never
            // had Find opened never allocates one, matching
            // `editorStore.existingSystem(for:)`'s own lazy convention used
            // just below for the status bar.
            if let findModel = findStore.existingModel(for: identity), findModel.isActive {
                FindBarView(
                    model: findModel,
                    text: text,
                    resolvedText: { editorStore.existingSystem(for: identity)?.text ?? text },
                    resolvedSelection: { editorStore.existingSystem(for: identity)?.selectedRange },
                    initialAnchor: editorStore.existingSystem(for: identity)?.selectedRange.location ?? 0,
                    onMatchesChanged: { reveal, navigationToken in
                        applyFindHighlights(findModel, reveal: reveal, navigationToken: navigationToken)
                    },
                    onNavigationIntent: { coordinator?.folderSearchNavigationDidChange() ?? 0 },
                    onClose: { closeFindBar(findModel) },
                    onReplace: { applyFindReplacement($0, model: findModel) },
                    onSelectAll: { applySelectAllMatches($0) }
                )
                // The "In Selection" domain follows every edit while Find is open.
                .onAppear {
                    editorStore.existingSystem(for: identity)?.textChangeObserver = { [weak findModel] change in
                        findModel?.noteTextChange(change)
                    }
                }
                .onDisappear {
                    editorStore.existingSystem(for: identity)?.textChangeObserver = nil
                }
            }

            EditorView(
                text: $text,
                identity: identity,
                configuration: editorConfiguration,
                store: editorStore,
                onSelectionChange: { range in
                    statusBarSelection = range
                    outlineController.referenceOffsetDidChange(range.location)
                    outlineController.jsonReferenceOffsetDidChange(range.location)
                },
                onScrollChange: { offset in
                    handleEditorScroll(utf16Offset: offset)
                    outlineController.jsonReferenceOffsetDidChange(offset)
                },
                onLayoutChange: {
                    coordinator?.folderSearchEditorLayoutChanged(tabID: identity)
                    coordinator?.finishMathSourceNavigation(in: model, identity: identity, session: mathSession)
                }
            )
            .accessibilityIdentifier("editorPane")
            .overlay(alignment: .bottomTrailing) {
                // With the status bar hidden, the reduced-highlighting note
                // still needs a non-modal home (register row H5).
                if appSettings?.editor.showsStatusBar == false,
                   let note = ReducedHighlightingNote(highlightStore.state(for: identity)) {
                    ReducedHighlightingNoteView(note: note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
            }
            .task(id: identity) {
                attachHighlighter()
            }

            // `system.text`/`system.lineIndex` are read together from the SAME
            // live `EditorTextSystem`, not from the `text` SwiftUI binding:
            // the binding is only as current as the last SwiftUI render pass,
            // while `system.lineIndex` reflects the text system's real,
            // synchronous state. Mixing the two crashed
            // `EditorLineIndex.column(atUTF16Offset:onLine:in:)` with an
            // out-of-bounds substring range the moment a filter or other
            // programmatic edit changed the text system faster than SwiftUI
            // re-rendered `text` (found by `TextFilterCoordinatorTests`'
            // real, mounted-window integration test).
            if appSettings?.editor.showsStatusBar != false,
               let system = editorStore.existingSystem(for: identity) {
                let metrics = system.documentMetrics()
                EditorStatusBarView(
                    source: system.liveTextSource,
                    metrics: metrics,
                    selectedRange: statusBarSelection,
                    lineIndex: system.lineIndex,
                    indentationWidth: appSettings?.editor.indentationWidth ?? 4,
                    convertsTabsToSpaces: appSettings?.editor.convertsTabsToSpaces ?? true,
                    onGoToLine: { coordinator?.toggleGoToLine() },
                    encoding: EncodingStatusItem(
                        metadata: document.encoding,
                        isChangeable: document.hasEncodableBackingFile,
                        onReopen: { coordinator?.reopenDocument(in: model, withEncoding: $0) },
                        onSave: { coordinator?.saveDocument(in: model, withEncoding: $0) }
                    ),
                    lineEnding: LineEndingStatusItem(
                        profile: metrics.lineEndings,
                        onConvert: { [weak system] in
                            guard let system, system.convertLineEndings(to: $0) else { return }
                            system.textView.window?.makeFirstResponder(system.textView)
                        }
                    ),
                    syntaxMode: syntaxModeItem,
                    reducedHighlighting: ReducedHighlightingNote(highlightStore.state(for: identity))
                )
            }
        }
    }

    /// Forwards the editor's visible top line into the scroll-sync
    /// controller so the preview follows. `utf16Offset` comes from
    /// `EditorView`'s scroll callback (see `EditorTextSystem.topVisibleUTF16Offset`).
    ///
    /// Skips the outline update while `scrollController.isJumping`: an
    /// animated `revealSelection` (the outline's own jump) fires this
    /// callback once per frame of its ~0.2s scroll animation, and those
    /// mid-flight offsets don't yet reflect the jump's target — reading them
    /// back into the outline overwrote the correct highlight (already set
    /// synchronously by the jump's own selection change, below in
    /// `pendingJumpLineRange`) with a stale one, leaving the *previous*
    /// heading bolded after a jump landed correctly.
    func handleEditorScroll(utf16Offset: Int) {
        guard let sourceMap = parseSession.document?.sourceMap else { return }
        scrollController.editorDidScroll(toLine: sourceMap.line(atUTF16Offset: utf16Offset))
        guard !scrollController.isJumping else { return }
        outlineController.referenceOffsetDidChange(utf16Offset)
    }

    var syntaxModeItem: SyntaxModeStatusItem {
        SyntaxModeStatusItem(autoFormat: document.format, syntaxFormat: tab.syntaxFormat) { formatID in
            model.tabStore.setSyntaxMode(formatID, for: tab.id)
            coordinator?.scheduleSaveSession()
            if let system = editorStore.existingSystem(for: identity) {
                system.textView.window?.makeFirstResponder(system.textView)
            }
        }
    }

    func attachHighlighter() {
        guard let textSystem = editorStore.existingSystem(for: identity) else { return }
        _ = highlightStore.highlighter(
            for: identity,
            textSystem: textSystem,
            languageID: tab.syntaxFormat.highlightLanguageID,
            theme: themeController.current
        )
    }

    /// Pushes `model`'s current match list/index to the text view for
    /// highlighting, and reveals (selects + scrolls to) the current match —
    /// called by `FindBarView` after every query/option/text change and
    /// every Find Next/Previous, so the visible highlight and the live
    /// selection never lag behind the model by more than one SwiftUI update.
    func applyFindHighlights(
        _ model: EditorFindModel,
        reveal: Bool = true,
        navigationToken: UInt? = nil,
        navigationCoordinator: WindowCoordinator? = nil
    ) {
        // A result that lands after the bar was dismissed must not re-highlight or reselect.
        guard model.isActive, let system = editorStore.existingSystem(for: identity) else { return }
        system.setFindHighlights(ranges: model.matches.map(\.range), currentIndex: model.currentIndex)
        if reveal,
           let navigationToken,
           (navigationCoordinator ?? coordinator)?.folderSearchNavigationIsCurrent(navigationToken) == true,
           let current = model.currentMatch {
            system.revealSelection(utf16Range: current.range, flash: false, animated: true)
        }
    }

    /// Hides the Find bar and clears its highlighting — the model's own
    /// query/options/matches are left untouched so reopening Find on this
    /// tab (via `findStore`'s per-identity caching) restores exactly where
    /// the user left off.
    func closeFindBar(_ model: EditorFindModel) {
        model.isActive = false
        model.pendingRevealNavigationToken = nil
        model.cancelPendingSearch()
        model.clearSearchDomain()
        editorStore.existingSystem(for: identity)?.setFindHighlights(ranges: [], currentIndex: nil)
    }

    /// Applies a Replace/Replace All transaction `FindBarView` built
    /// (EPIC-22 §6.14, Slice 5b) to the live text system — this is the only
    /// thing that actually mutates the document; `EditorFindModel` itself
    /// never does (see that type's own doc comment). Re-runs the search
    /// against the POST-edit text afterward, anchored at the transaction's
    /// own `resultingSelection` (already computed as "right after the
    /// last thing this transaction replaced"), since every match after
    /// what was just replaced has shifted and the replacement text itself
    /// may have changed which text still matches at all.
    func applyFindReplacement(_ transaction: EditorEditTransaction, model: EditorFindModel) {
        guard let system = editorStore.existingSystem(for: identity) else { return }
        // The matches were computed against the text as of the last SwiftUI change pass; an active IME composition
        // (or one committed in this very click) changes the text without posting one, so applying now would write at
        // stale offsets (`にほんabarfoo`). Refuse, and search the live text so the next click works.
        guard system.canApplyCommandEdit, model.matchesAreCurrent(forLiveText: system.text) else {
            Task { await model.updateMatches(in: system.text, preferringLocationNear: nil) }
            return
        }
        system.apply(transaction)
        let anchor = transaction.resultingSelection?.primaryRange.location
        let navigationToken = coordinator?.folderSearchNavigationDidChange()
        Task {
            guard await model.updateMatches(in: system.text, preferringLocationNear: anchor),
                  model.isActive
            else { return }
            applyFindHighlights(model, navigationToken: navigationToken)
        }
    }

    /// Installs "Select All Matches" (EPIC-22 §6.14, Slice 5c) on the live
    /// text system. Deliberately does NOT call `revealSelection(utf16Range:)`
    /// afterward — that method collapses to a SINGLE range internally
    /// (`textView.setSelectedRange`), which would destroy the multi-selection
    /// this just installed. `scrollToVisible(utf16Range:)` only scrolls, so
    /// the primary match comes into view without touching selection at all.
    func applySelectAllMatches(
        _ selection: EditorSelectionSet,
        navigationCoordinator: WindowCoordinator? = nil
    ) {
        guard let system = editorStore.existingSystem(for: identity) else { return }
        // Installing a multi-selection is itself a user-driven navigation
        // intent. Invalidate any folder-search open that is still suspended
        // on file/root work before it can resume and collapse this selection.
        (navigationCoordinator ?? coordinator)?.folderSearchNavigationDidChange()
        system.selectionSet = selection
        system.scrollToVisible(utf16Range: selection.primaryRange)
    }
}
