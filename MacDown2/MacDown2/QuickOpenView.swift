import SwiftUI
import TextSearch

/// Quick Open's content (EPIC-22 §6.15, Slice 6b): a search field plus a
/// fuzzy-filtered file list, fully keyboard-operable — type to filter, arrow
/// keys to move the selection, Return to open, Escape to dismiss. Presented
/// in `QuickOpenPanel`. Structurally mirrors `CommandPaletteView` (same
/// field/list/keyboard shape); the two are not unified into one component
/// since Quick Open opens files while the palette invokes commands — issue
/// #117's own palette-consistency work stays scoped to Slice 9.
struct QuickOpenView: View {
    @Bindable var model: QuickOpenModel
    let onOpen: @MainActor (QuickOpenModel.PresentedResult) async -> Bool
    let onDismiss: () -> Void

    @FocusState private var searchFieldFocused: Bool
    @State private var isOpening = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to file…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(12)
                .focused($searchFieldFocused)
                .accessibilityLabel("Quick Open search")
                .accessibilityIdentifier("quickOpenSearchField")
                .disabled(isOpening)
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    openSelectedAndDismiss()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Divider()

            if model.results.isEmpty {
                Text(
                    model.isSearching ? "Searching…"
                        : model.isIndexUnavailable ? "Folder Unavailable" : "No Matching Files"
                )
                .foregroundStyle(.secondary)
                .padding()
                .accessibilityIdentifier("quickOpenEmptyState")
            } else {
                ScrollViewReader { proxy in
                    List(Array(model.results.enumerated()), id: \.element) { index, path in
                        QuickOpenRowView(path: path, isSelected: index == model.selectedIndex)
                            .id(path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.moveSelection(by: index - model.selectedIndex)
                                openSelectedAndDismiss()
                            }
                    }
                    .disabled(isOpening)
                    .listStyle(.plain)
                    .frame(maxHeight: 280)
                    .onChange(of: model.selectedIndex) { _, newValue in
                        guard let path = model.results[safe: newValue] else { return }
                        proxy.scrollTo(path)
                    }
                }
            }
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .onAppear {
            model.refresh()
            searchFieldFocused = true
        }
    }

    private func openSelectedAndDismiss() {
        guard !isOpening, let selected = model.selectedResult else { return }
        isOpening = true
        Task { @MainActor in
            if await onOpen(selected) {
                onDismiss()
            } else {
                isOpening = false
                model.refresh()
            }
        }
    }
}

private struct QuickOpenRowView: View {
    let path: IndexedPath
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // File/directory names, not user-facing UI strings — never
            // translated, matching `CommandPaletteRowView`'s own
            // `Text(verbatim:)` use for the same reason.
            Text(verbatim: path.basename)
            Text(verbatim: path.relativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quickOpenRow.\(path.relativePath)")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(path.basename), \(path.relativePath)")
    }
}
