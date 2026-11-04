import SwiftUI

/// The command palette's content (epic-14-implementation.md §12, §17
/// Slice 7): a search field plus a type-to-filter list combining app
/// commands and discovered text filters, fully keyboard-operable — type to
/// filter, arrow keys to move the selection, Return to invoke, Escape to
/// dismiss. Presented in `CommandPalettePanel`.
struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let coordinator: WindowCoordinator
    /// The document window the palette was opened from, captured before
    /// presentation. Commands target this explicitly rather than
    /// `NSApp.keyWindow`, which is the palette panel itself while this view
    /// is on screen (post-review finding #7).
    let originController: WindowController?
    let onDismiss: () -> Void

    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(12)
                .focused($searchFieldFocused)
                .accessibilityLabel("Command palette search")
                .accessibilityIdentifier("commandPaletteSearchField")
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    invokeSelectedAndDismiss()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Divider()

            if model.rows.isEmpty {
                Text("No Matching Commands")
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityIdentifier("commandPaletteEmptyState")
            } else {
                ScrollViewReader { proxy in
                    List(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        CommandPaletteRowView(row: row, isSelected: index == model.selectedIndex)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.moveSelection(by: index - model.selectedIndex)
                                invokeSelectedAndDismiss()
                            }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 280)
                    .onChange(of: model.selectedIndex) { _, newValue in
                        guard let row = model.rows[safe: newValue] else { return }
                        proxy.scrollTo(row.id)
                    }
                }
            }
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .onAppear {
            model.refreshRows()
            searchFieldFocused = true
        }
    }

    private func invokeSelectedAndDismiss() {
        model.invokeSelected(
            coordinator: coordinator,
            originController: originController,
            appHandler: { command, coordinator, controller in command.action(coordinator, controller) },
            filterHandler: { command in
                // Resolved against the captured origin controller, not
                // `NSApp.keyWindow` — by the time this `Task` runs, the
                // palette may already be the key window (post-review
                // finding #7).
                guard let originController,
                      let target = coordinator.textFilterCoordinator.editingTarget(for: originController)
                else { return }
                Task { await coordinator.textFilterCoordinator.run(command, against: target) }
            }
        )
        onDismiss()
    }
}

private struct CommandPaletteRowView: View {
    let row: CommandPaletteRow
    let isSelected: Bool

    var body: some View {
        HStack {
            // Mixes app command names with user-authored text-filter script
            // names, so this can't assume everything here is translatable.
            Text(verbatim: row.title)
            Spacer()
            if row.kind == .textFilter {
                Text("Command")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commandPaletteRow.\(row.id)")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(row.kind == .textFilter ? String(localized: "\(row.title), user command") : row.title)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
