import EditorCore
import SwiftUI
import TextSearch

/// The current-document Find bar (EPIC-22 §6.14, Slice 5a): an inline bar
/// docked above the editor — not a floating `NSPanel` like `GoToLinePanel`/
/// `CommandPalettePanel` — matching every comparable editor's own find UI
/// and §6.14's explicit departure from this codebase's two existing
/// floating-panel precedents. Pure presentation: all find/navigate state and
/// logic lives in the bound `EditorFindModel`; this view's own job is typing
/// query/option changes into it, re-running the search whenever the query,
/// options, or underlying document text changes, and reporting the result
/// back up via `onMatchesChanged` so the caller can push highlight ranges to
/// the text view and reveal the current match.
struct FindBarView: View {
    @Bindable var model: EditorFindModel
    /// The SwiftUI-observed document text: used ONLY as a reactive trigger
    /// (`.onChange(of: text)` below) so a live edit re-runs the search.
    /// Never read directly to build the search input — see `resolvedText`.
    let text: String
    /// Returns the text to actually search, read fresh at the moment of
    /// each search rather than captured once. Callers pass
    /// `editorStore.existingSystem(for:)?.text`, the live `EditorTextSystem`'s
    /// own text — NOT this view's own `text` prop above: `DocumentEditorSplitView`'s
    /// own established precedent (`EditorStatusBarView(text: system.text, ...)`,
    /// with a doc comment on exactly this) is that the SwiftUI `text`
    /// binding can trail the live text system by up to one render pass
    /// while `EditorTextSystem.isPerformingProgrammaticTextUpdate` is set
    /// (an external file reload/conflict-resolution replacement
    /// deliberately skips publishing it, `EditorView.swift`'s
    /// `textDidChange`) — searching that stale snapshot instead of the
    /// live text could highlight/select the wrong location for one frame.
    let resolvedText: () -> String
    /// Returns the live selection/caret range, read fresh at the moment of
    /// each search — same "read live, never capture once" discipline as
    /// `resolvedText`. Used only to implement `options.searchesSelectionOnly`
    /// (EPIC-22 §6.14, Slice 5c); ignored entirely unless that option is on.
    let resolvedSelection: () -> NSRange?
    /// The caret location at the moment the bar was shown, used ONLY by the
    /// very first search on `.onAppear` — so opening Find starts searching
    /// forward from where the user actually was, matching every comparable
    /// editor's own convention, rather than always jumping to the first
    /// match in the document. Every later re-search (query/option/text
    /// change, or explicit Find Next/Previous) anchors off `model`'s own
    /// current match instead, per `recomputeMatches`.
    let initialAnchor: Int
    /// Called after `model.matches`/`model.currentIndex` changes for any
    /// reason (query edit, option toggle, live text edit, Find Next/
    /// Previous) so the caller can push highlight ranges to the text view
    /// and reveal the new current match. Never called with stale state —
    /// this view always updates `model` first, synchronously, before
    /// calling this.
    /// `reveal` is false when the matches were recomputed only because the DOCUMENT
    /// changed (the user is typing in the editor): highlights refresh but the
    /// selection must not move onto the current match, or the next keystroke would
    /// replace the matched text.
    let onMatchesChanged: (_ reveal: Bool, _ navigationToken: UInt?) -> Void
    let onNavigationIntent: () -> UInt
    let onClose: () -> Void
    /// EPIC-22 §6.14, Slice 5b: called with the transaction Replace/Replace
    /// All built (`EditorFindModel.replaceCurrentTransaction(with:)`/
    /// `replaceAllTransaction(with:)`) so the caller can apply it to the
    /// live `EditorTextSystem` — this view never mutates text itself,
    /// matching `EditorFindModel`'s own "never mutates live text" contract.
    let onReplace: (EditorEditTransaction) -> Void
    /// EPIC-22 §6.14, Slice 5c: called with the `EditorSelectionSet` "Select
    /// All Matches" built, so the caller can install it on the live
    /// `EditorTextSystem`. This view never touches selection itself.
    let onSelectAll: (EditorSelectionSet) -> Void

    @FocusState private var isQueryFocused: Bool
    @Environment(\.windowCoordinator) private var coordinator

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($isQueryFocused)
                        .accessibilityIdentifier("findBarQueryField")
                        .onKeyPress(phases: .down) { press in
                            switch press.key {
                            case .return:
                                if press.modifiers.contains(.shift) {
                                    navigate(model.findPrevious)
                                } else {
                                    navigate(model.findNext)
                                }
                                return .handled
                            case .escape:
                                onClose()
                                return .handled
                            default:
                                return .ignored
                            }
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(minWidth: 200, maxWidth: 320)

                optionToggle("Aa", isOn: $model.options.isCaseSensitive, help: String(localized: "Case Sensitive"))
                optionToggle(
                    String(localized: "W"),
                    isOn: $model.options.isWholeWord,
                    help: String(localized: "Whole Word")
                )
                optionToggle(".*", isOn: $model.options.isRegex, help: String(localized: "Regular Expression"))
                optionToggle(
                    String(localized: "Sel"),
                    isOn: $model.options.searchesSelectionOnly,
                    help: String(localized: "In Selection")
                )

                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("findBarSearching")
                }

                statusLabel

                Spacer(minLength: 0)

                Button {
                    navigate(model.findPrevious)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(model.matchCount == 0)
                .help("Find Previous")
                .accessibilityIdentifier("findBarPreviousButton")

                Button {
                    navigate(model.findNext)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(model.matchCount == 0)
                .help("Find Next")
                .accessibilityIdentifier("findBarNextButton")

                Button {
                    selectAllMatches()
                } label: {
                    Image(systemName: "selection.pin.in.out")
                }
                .disabled(model.matchCount == 0)
                .help("Select All Matches")
                .accessibilityIdentifier("findBarSelectAllButton")

                Divider().frame(height: 16)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close (Esc)")
                .accessibilityIdentifier("findBarCloseButton")
            }

            replaceRow
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("findBar")
        .onAppear {
            // Deferred one turn: set synchronously in `onAppear`, the focus
            // request never took effect (`isQueryFocused` never changed and
            // the editor stayed first responder), so typing after ⌃F went
            // into the document instead of the query.
            Task { @MainActor in
                await Task.yield()
                isQueryFocused = true
            }
            let navigationToken = model.pendingRevealNavigationToken
            model.pendingRevealNavigationToken = nil
            recomputeMatches(
                anchor: model.currentMatch?.range.location ?? initialAnchor,
                sampleSelection: true,
                reveal: navigationToken != nil,
                navigationToken: navigationToken
            )
        }
        // Opening the bar moves first responder into the query field on a
        // later SwiftUI pass, after the ⌃F key event already re-validated the
        // menus, so the Format menu kept offering Bold for the editor. Same
        // fix as `SidebarView`'s Focus Outline: re-validate once the focus
        // change has been applied (found by the first real run of
        // `EditingAssistsUITests`).
        .onChange(of: isQueryFocused) { _, _ in
            Task { @MainActor in
                await Task.yield()
                coordinator?.commandStateDidChange()
            }
        }
        // Literal search distinguishes canonically equal but byte-distinct
        // queries, so Swift's normal String equality is not a refresh trigger.
        .onChange(of: ExactTextFingerprint(model.query)) { _, _ in
            recomputeMatches(anchor: model.currentMatch?.range.location)
        }
        .onChange(of: model.options) { old, new in
            recomputeMatches(
                anchor: model.currentMatch?.range.location,
                sampleSelection: new.searchesSelectionOnly && !old.searchesSelectionOnly
            )
        }
        // Exact content identity, not `String` equality: a canonically-equal but byte-distinct change (U+00C5 → U+212B)
        // is a real edit that must refresh the matches.
        .onChange(of: ExactTextFingerprint(text)) { _, _ in
            recomputeMatches(anchor: model.currentMatch?.range.location, reveal: false)
        }
    }

    /// Always shown alongside the query row (not a collapsible "expand for
    /// replace" toggle — the simplest complete shape for this slice, and a
    /// standard one: e.g. Sublime Text's default Find bar does the same).
    private var replaceRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                TextField("Replace", text: $model.replacementText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("findBarReplaceField")
                    .onKeyPress(phases: .down) { press in
                        switch press.key {
                        case .return:
                            replaceCurrent()
                            return .handled
                        case .escape:
                            onClose()
                            return .handled
                        default:
                            return .ignored
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(minWidth: 200, maxWidth: 320)

            Button("Replace") {
                replaceCurrent()
            }
            .buttonStyle(.bordered)
            .disabled(model.currentMatch == nil || model.isSearching)
            .accessibilityIdentifier("findBarReplaceButton")

            Button("Replace All") {
                replaceAll()
            }
            .buttonStyle(.bordered)
            .disabled(model.matchCount == 0 || model.isSearching)
            .accessibilityIdentifier("findBarReplaceAllButton")

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let error = model.error {
            Text(errorMessage(for: error))
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .accessibilityIdentifier("findBarError")
        } else if model.query.isEmpty {
            EmptyView()
        } else if model.matchCount == 0 {
            Text("No Results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("findBarStatus")
        } else {
            Text("\((model.currentIndex ?? 0) + 1) of \(model.matchCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("findBarStatus")
        }
    }

    private func errorMessage(for error: SearchQueryError) -> String {
        switch error {
        case let .invalidRegex(message): message
        // `EditorFindModel` never stores a cancelled search as its error; this
        // only keeps the switch exhaustive.
        case .cancelled: String(localized: "Search cancelled")
        }
    }

    /// Runs `navigation` (`model.findNext`/`findPrevious`), then reports the
    /// resulting state up — used by both the keyboard (Return/Shift-Return)
    /// and the toolbar chevron buttons so both paths behave identically.
    private func navigate(_ navigation: () -> SearchMatch?) {
        let navigationToken = onNavigationIntent()
        _ = navigation()
        onMatchesChanged(true, navigationToken)
    }

    /// `updateMatches(in:)` runs off-main and can be superseded by a later
    /// call before it resolves (rapid typing, or a slow/pathological regex
    /// still in flight) — see that method's own doc comment. When that
    /// happens it returns `false` and this skips `onMatchesChanged()`
    /// entirely, since `model`'s own state was left untouched by the
    /// discarded call and re-announcing it would be a redundant, no-op
    /// re-application of whatever the current, still-authoritative state
    /// already is.
    private func recomputeMatches(
        anchor: Int?,
        sampleSelection: Bool = false,
        reveal: Bool = true,
        navigationToken: UInt? = nil
    ) {
        let text = resolvedText()
        // Sampled only when "In Selection" is being (re)established; every
        // other refresh uses the model's retained domain (#183 F03).
        let selection = sampleSelection ? resolvedSelection() : nil
        let intentToken = reveal ? (navigationToken ?? onNavigationIntent()) : nil
        Task {
            guard await model.updateMatches(in: text, selection: selection, preferringLocationNear: anchor),
                  model.isActive
            else {
                return
            }
            onMatchesChanged(reveal, intentToken)
        }
    }

    /// A no-op (not an error) when there's no current match to replace, or
    /// while a search is still in flight — mirrors the disabled state of
    /// the "Replace" button, but this guard is what actually matters: the
    /// Return key inside the replace field calls this method directly,
    /// bypassing the button's own `.disabled` modifier entirely. Without
    /// the `isSearching` check, a Replace fired while `updateMatches(in:)`
    /// is still resolving (e.g. a slow regex, or the user kept typing) would
    /// build a transaction from the OLD, pre-edit `matches`/`currentMatch` —
    /// positions computed against text or a query that no longer applies —
    /// and apply it straight to the CURRENT live text, silently replacing
    /// whatever unrelated content now sits at that stale offset. A hostile
    /// review of this exact slice found this gap; §6.14 never disclosed it
    /// as an accepted risk, so this is a genuine fix, not new scope.
    private func replaceCurrent() {
        guard !model.isSearching, let transaction = model.replaceCurrentTransaction(with: model.replacementText)
        else { return }
        onReplace(transaction)
    }

    /// See `replaceCurrent()`'s own doc comment — the same staleness risk
    /// applies here, at N matches instead of one.
    private func replaceAll() {
        guard !model.isSearching, let transaction = model.replaceAllTransaction(with: model.replacementText) else {
            return
        }
        onReplace(transaction)
    }

    /// A no-op while a search is still in flight, same staleness reasoning
    /// as `replaceCurrent()`/`replaceAll()` — installing a selection built
    /// from stale, pre-edit match positions would put the caret(s) at the
    /// wrong offsets. Closes the bar afterward, matching every comparable
    /// editor's own "Select All Matches hands off to ordinary multi-cursor
    /// editing" convention — the Find bar has done its job once the
    /// selection is installed.
    private func selectAllMatches() {
        guard !model.isSearching, let selection = model.selectionSetForAllMatches else { return }
        onSelectAll(selection)
        onClose()
    }
}

extension FindBarView {
    private func optionToggle(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 20)
        }
        .buttonStyle(.bordered)
        .tint(isOn.wrappedValue ? Color.accentColor : Color.clear)
        .help(help)
    }
}
