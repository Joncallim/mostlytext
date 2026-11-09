import EditorCore
import SwiftUI

/// The Insert Snippet picker's content (EPIC-22 §6.18, Slice 9e): type to
/// filter by name, arrows to move, Return to insert, Escape to dismiss.
/// Structurally mirrors `QuickOpenView`.
struct SnippetPickerView: View {
    @Bindable var model: SnippetPickerModel
    /// Returns whether the insert happened; the picker stays open when it did not.
    let onInsert: (Snippet) -> Bool
    let onDismiss: () -> Void

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Insert snippet…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(12)
                .focused($searchFieldFocused)
                .accessibilityLabel("Insert Snippet search")
                .accessibilityIdentifier("snippetPickerSearchField")
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    insertSelectedAndDismiss()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Divider()

            if model.results.isEmpty {
                Text(model.snippets.isEmpty ? "No Snippets Available" : "No Matching Snippets")
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("snippetPickerEmptyState")
            } else {
                ScrollViewReader { proxy in
                    List(Array(model.results.enumerated()), id: \.element.id) { index, snippet in
                        SnippetPickerRowView(snippet: snippet, isSelected: index == model.selectedIndex)
                            .id(snippet.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.select(at: index)
                                insertSelectedAndDismiss()
                            }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 280)
                    .onChange(of: model.selectedIndex) { _, newValue in
                        guard model.results.indices.contains(newValue) else { return }
                        proxy.scrollTo(model.results[newValue].id)
                    }
                }
            }
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("snippetPickerNotice")
            }
        }
        .onAppear { searchFieldFocused = true }
    }

    private func insertSelectedAndDismiss() {
        guard let selected = model.selectedSnippet else { return }
        if onInsert(selected) {
            onDismiss()
        }
    }
}

private struct SnippetPickerRowView: View {
    let snippet: Snippet
    let isSelected: Bool

    var body: some View {
        // User names are verbatim data; built-in display names are already
        // resolved from EditorCore's catalog before reaching this view.
        Text(verbatim: snippet.name)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("snippetPickerRow.\(snippet.id)")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(snippet.name)
    }
}
