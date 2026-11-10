import OutlineUI
import SwiftUI
import Workspace

struct OutlineRowView: View {
    let item: OutlineItem
    let depth: Int
    @Bindable var outlineController: OutlineController

    var body: some View {
        HStack(spacing: 4) {
            if item.children.isEmpty {
                Color.clear.frame(width: 12, height: 12)
            } else {
                Button(action: toggleCollapsed) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? Text("Expand") : Text("Collapse"))
            }
            Text(verbatim: item.title.isEmpty ? String(localized: "Untitled section") : item.title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(
                    item.title.isEmpty ? AnyShapeStyle(.tertiary) :
                        (isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                )
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { outlineController.activate(item.id) })
    }

    private var isCollapsed: Bool {
        outlineController.collapsedItemIDs.contains(item.id)
    }

    private var isCurrent: Bool {
        outlineController.currentItemID == item.id
    }

    private func toggleCollapsed() {
        if isCollapsed {
            outlineController.collapsedItemIDs.remove(item.id)
        } else {
            outlineController.collapsedItemIDs.insert(item.id)
        }
    }
}

extension SidebarSection {
    var title: String {
        switch self {
        case .folder: String(localized: "Folder")
        case .outline: String(localized: "Outline")
        case .search: String(localized: "Search")
        }
    }

    var systemImage: String {
        switch self {
        case .folder: "folder"
        case .outline: "list.bullet"
        case .search: "magnifyingglass"
        }
    }
}
