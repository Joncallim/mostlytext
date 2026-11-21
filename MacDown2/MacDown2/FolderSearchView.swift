import SwiftUI
import TextSearch

/// Folder search's sidebar content (EPIC-22 §6.16, Slice 7b): a search
/// field plus results grouped by file, streamed in as `FolderSearchModel`
/// finds them. Embedded directly in `SidebarView`'s own `List` (inside the
/// `.search` section's `DisclosureGroup`, like `.folder`/`.outline`), not a
/// floating panel — see `SidebarSection.search`'s own doc comment for why.
///
/// Each result row shows the matched file and its match count; activating
/// a row opens that file and reveals its first match
/// (`WindowCoordinator.openFolderSearchResult`), the same "open via the
/// existing document-open path" precedent Quick Open already established
/// (§6.15). Per-match line/column and a contextual excerpt (issue #112's
/// own "file, line, column and contextual excerpt") are deferred to a
/// follow-up polish pass — `SearchMatch` itself only carries a UTF-16
/// range today, and computing an excerpt per match would mean re-reading
/// file content the engine has already discarded once matching finished;
/// this is a real, disclosed gap, not something to silently skip.
struct FolderSearchView: View {
    @Environment(\.locale) private var locale
    @Bindable var model: FolderSearchModel
    let onOpen: (FolderSearchModel.PresentedResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("Search in Folder…", text: $model.query)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 4)
                    .disabled(model.isReplacing)
                    .accessibilityLabel("Folder search")
                    .accessibilityIdentifier("folderSearchField")
                Button {
                    model.isReplaceVisible.toggle()
                } label: {
                    Image(systemName: model.isReplaceVisible ? "chevron.up" : "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Show or hide Replace")
                .accessibilityLabel("Toggle Replace in Folder")
                .accessibilityIdentifier("folderReplaceToggle")
            }

            if model.isReplaceVisible {
                replaceControls
            }

            statusLine
            replaceSummaryView
        }
        .padding(.horizontal, 4)
        .confirmationDialog(
            confirmationTitle,
            isPresented: $model.isConfirmingReplace,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) { model.confirmReplace() }
                .accessibilityIdentifier("folderReplaceConfirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This rewrites the files on disk and cannot be undone. Files open with unsaved changes are skipped."
            )
        }

        ForEach(model.presentedResults) { presented in
            let fileMatch = presented.match
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if model.isReplaceVisible {
                        Toggle(
                            isOn: Binding(
                                get: {
                                    model.isCurrentResult(presented)
                                        && model.isIncluded(path: fileMatch.relativePath)
                                },
                                set: { model.setIncluded($0, result: presented) }
                            )
                        ) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(model.isReplacing || !model.isCurrentResult(presented))
                            .accessibilityLabel("Include \(fileMatch.relativePath) in Replace")
                            .accessibilityIdentifier("folderReplaceInclude-\(fileMatch.relativePath)")
                    }
                    Button {
                        onOpen(presented)
                    } label: {
                        FolderSearchResultRow(fileMatch: fileMatch)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isCurrentResult(presented))
                    .accessibilityIdentifier("folderSearchResult-\(fileMatch.relativePath)")
                    if model.isReplaceVisible {
                        Button {
                            model.togglePreview(result: presented)
                        } label: {
                            Image(
                                systemName: model.expandedPaths.contains(fileMatch.relativePath)
                                    ? "chevron.down" : "chevron.right"
                            )
                        }
                        .buttonStyle(.borderless)
                        .disabled(!model.isCurrentResult(presented))
                        .help("Preview replacements")
                        .accessibilityLabel("Preview replacements in \(fileMatch.relativePath)")
                        .accessibilityIdentifier("folderReplacePreviewToggle-\(fileMatch.relativePath)")
                    }
                }
                if model.isReplaceVisible, model.isCurrentResult(presented),
                   model.expandedPaths.contains(fileMatch.relativePath) {
                    FolderReplacePreviewView(preview: model.previews[fileMatch.relativePath])
                }
            }
        }
    }

    private var confirmationTitle: String {
        let files = model.includedResults.count
        let matches = model.includedMatchCount
        return FolderSearchCountCopy.confirmation(matches: matches, files: files).message(locale: locale)
    }

    @ViewBuilder
    private var replaceControls: some View {
        TextField("Replace with…", text: $model.replacement)
            .textFieldStyle(.plain)
            .padding(.vertical, 4)
            .disabled(model.isReplacing)
            .accessibilityLabel("Replacement text")
            .accessibilityIdentifier("folderReplaceField")
        HStack {
            Button("Replace All") { model.requestReplace() }
                .disabled(!model.canReplace)
                .accessibilityIdentifier("folderReplaceAll")
            if model.isReplacing {
                Button("Stop") { model.cancelReplace() }
                    .accessibilityIdentifier("folderReplaceStop")
                Text(verbatim: FolderSearchCountCopy.replaceProgress(
                    completed: model.replaceCompleted, total: model.replaceTotal
                ).message(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("folderReplaceProgress")
            }
        }
        if model.unsearchedFileCount > 0, !model.isSearching, model.outcome != nil {
            Text(verbatim: FolderSearchCountCopy.unsearched(files: model.unsearchedFileCount).message(locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderReplaceUnsearched")
        }
        if case .truncated = model.outcome, !model.isSearching {
            Text("Replace is unavailable while results are truncated.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderReplaceUnavailable")
        }
        if case .timedOut = model.outcome, !model.isSearching {
            Text("Replace is unavailable while search results are incomplete.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderReplaceUnavailable")
        }
    }

    @ViewBuilder
    private var replaceSummaryView: some View {
        if let summary = model.replaceSummary {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: FolderSearchCountCopy.summary(
                    matches: summary.replacedMatches, files: summary.replacedFiles
                ).message(locale: locale))
                    .font(.caption)
                    .accessibilityIdentifier("folderReplaceSummary")
                ForEach(summary.skipped.prefix(Self.skippedRowLimit), id: \.relativePath) { skipped in
                    Text(verbatim: "\(skipped.relativePath) — \(Self.reason(for: skipped.outcome))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("folderReplaceSkipped-\(skipped.relativePath)")
                }
                if summary.skipped.count > Self.skippedRowLimit {
                    Text(verbatim: FolderSearchCountCopy.skipped(
                        files: summary.skipped.count - Self.skippedRowLimit
                    ).message(locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let skippedRowLimit = 50

    private static func reason(for outcome: ReplacementFileOutcome) -> String {
        switch outcome {
        case .replaced: ""
        case .skippedChangedSinceSearch: String(localized: "changed since the search; not modified")
        case .skippedUnreadable: String(localized: "could not be read; not modified")
        case .skippedSymbolicLink: String(localized: "is a symbolic link; not modified")
        case .skippedOpenDocumentWithUnsavedChanges: String(localized: "open with unsaved changes; not modified")
        case .skippedCannotRepresent: String(localized: "cannot be rewritten safely; not modified")
        case let .failed(message): message
        case .notAttempted: String(localized: "stopped before this file")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch (model.query.isEmpty, model.isSearching, model.outcome) {
        case (true, _, _):
            EmptyView()
        case (false, true, _):
            Text("Searching…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, .truncated):
            Text("Results truncated — refine your search")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, .timedOut):
            Text("Search took too long — results are incomplete")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, .indexUnavailable):
            Text("Folder Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, _) where model.results.isEmpty:
            Text("No Results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, _):
            EmptyView()
        }
    }
}

private struct FolderSearchResultRow: View {
    @Environment(\.locale) private var locale
    let fileMatch: FolderSearchMatch

    var body: some View {
        HStack {
            // A file's own relative path, not user-facing UI text — never
            // translated, matching `QuickOpenRowView`'s own `Text(verbatim:)`
            // use for the same reason.
            Text(verbatim: fileMatch.relativePath)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text(verbatim: "\(fileMatch.matches.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: FolderSearchCountCopy.result(
            path: fileMatch.relativePath, matches: fileMatch.matches.count
        ).message(locale: locale)))
    }
}

private struct FolderReplacePreviewView: View {
    @Environment(\.locale) private var locale
    let preview: ReplacementFilePreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch preview {
            case nil:
                Text("Loading preview…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case let .lines(lines, total):
                ForEach(lines, id: \.lineNumber) { line in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(line.lineNumber)  − \(line.before)")
                            .foregroundStyle(.red)
                        Text(verbatim: "\(line.lineNumber)  + \(line.after)")
                            .foregroundStyle(.green)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Line \(line.lineNumber): \(line.before) becomes \(line.after)")
                }
                if total > lines.count {
                    Text(verbatim: FolderSearchCountCopy.previewRemaining(
                        matches: total - lines.count
                    ).message(locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .changedSinceSearch:
                Text("This file changed since the search; it will be skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unreadable:
                Text("This file could not be read; it will be skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .symbolicLink:
                Text("This file is a symbolic link; it will be skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 20)
        .accessibilityIdentifier("folderReplacePreview")
    }
}
