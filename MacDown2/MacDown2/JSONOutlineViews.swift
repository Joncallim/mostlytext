import JSONSupport
import OutlineUI
import SwiftUI

/// One JSON outline row — the format-neutral sibling of `OutlineRowView`
/// (EPIC-11 §3.4). Path-based IDs keep collapse/selection state stable
/// across edits and formatting.
struct JSONOutlineRowView: View {
    let item: ContentOutlineItem
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
        .simultaneousGesture(TapGesture().onEnded { outlineController.activateJSON(item.id) })
        .accessibilityIdentifier("jsonOutlineRow-\(item.id)")
    }

    private var isCollapsed: Bool {
        outlineController.jsonCollapsedItemIDs.contains(item.id)
    }

    private var isCurrent: Bool {
        outlineController.jsonCurrentItemID == item.id
    }

    private func toggleCollapsed() {
        if isCollapsed {
            outlineController.jsonCollapsedItemIDs.remove(item.id)
        } else {
            outlineController.jsonCollapsedItemIDs.insert(item.id)
        }
    }
}

/// The JSON preview pane: the outline tree rendered as the preview content,
/// sharing collapse/selection state with the sidebar through the controller.
struct JSONOutlinePreviewView: View {
    @Bindable var outlineController: OutlineController

    var body: some View {
        switch outlineController.jsonAvailability {
        case .notParsed:
            EmptyView()
                .accessibilityIdentifier("jsonOutlineEmptyState")
        case .invalidJSON:
            invalidState
        case .ready:
            // `.accessibilityIdentifier` on this container is best-effort, not
            // a reliable test hook: a SwiftUI `List` bridges to an AppKit
            // `NSOutlineView`-hosted AX subtree, and empirically its own
            // container-level identifier does not attach the way it does for
            // ordinary SwiftUI views (confirmed via a real accessibility-tree
            // dump — every row keeps its own `jsonOutlineRow-*` identifier
            // correctly, but the List's own identifier is not exposed).
            // `MultiFormatUITests` locates this pane by row content instead.
            List(rows) { row in
                JSONOutlineRowView(item: row.item, depth: row.depth, outlineController: outlineController)
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("jsonOutlinePreviewPane")
        case .unsupportedFormat, .noHeadings:
            EmptyView()
        }
    }

    private var rows: [JSONOutlineRow] {
        JSONOutlineBuilder.visibleRows(
            outlineController.jsonItems,
            collapsed: outlineController.jsonCollapsedItemIDs
        )
    }

    private var invalidState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            if let diagnostic = outlineController.jsonDiagnostic {
                Text("Line \(diagnostic.line), column \(diagnostic.column): \(diagnostic.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jsonInvalidState")
    }
}
