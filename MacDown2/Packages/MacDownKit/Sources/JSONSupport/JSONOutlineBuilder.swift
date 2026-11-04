import Foundation

/// A source-neutral outline node (EPIC-11 §3.4).
///
/// IDs encode the node's JSON path: object keys (`parent.key`) and array
/// indices (`parent[0]`), rooted at `$`. Duplicate-key documents are rejected
/// before outline construction, so a key path is unambiguous; repeated array
/// elements remain distinct by index. Paths remain remappable across edits
/// and formatting because they are derived from structure, not ordinals.
public struct ContentOutlineItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// 1-based physical line span of the node's value.
    public let lineRange: ClosedRange<Int>
    /// Half-open UTF-16 code-unit range of the node's value (no surrounding
    /// whitespace) — directly usable as an `NSRange` for editor jumps.
    public let sourceRange: Range<Int>
    public let children: [ContentOutlineItem]

    public init(
        id: String,
        title: String,
        lineRange: ClosedRange<Int>,
        sourceRange: Range<Int>,
        children: [ContentOutlineItem]
    ) {
        self.id = id
        self.title = title
        self.lineRange = lineRange
        self.sourceRange = sourceRange
        self.children = children
    }
}

/// Builds the collapsible JSON outline (EPIC-11 §3.4).
///
/// Label policy:
/// - Object members: the key when the value is an object or array (empty
///   containers get a `{ }`/`[ ]` suffix); the scalar's literal text when the
///   value is a scalar (decoded strings, numbers, `true`/`false`/`null`).
/// - Array elements: `[index]` (empty containers: `[index] { }`/`[index] [ ]`;
///   scalar elements show their literal text).
/// - The root object is `Object`, the root array is `Array`, and scalar roots
///   show their literal text.
///
/// Node policy: the complete tree is built with no truncation; the 10,000-node
/// performance test bounds the practical size. Invalid JSON yields the
/// parser's diagnostic and no items.
public enum JSONOutlineBuilder {
    public static func outline(_ text: String) -> JSONOutlineOutcome {
        switch JSONParser.parse(text) {
        case let .invalid(diagnostic):
            .invalid(diagnostic)
        case let .valid(node):
            .valid([build(node, path: "$", title: rootTitle(node), depth: 0)])
        }
    }

    /// The flat, collapse-aware row list for sidebar rendering.
    public static func visibleRows(_ items: [ContentOutlineItem], collapsed: Set<String>) -> [JSONOutlineRow] {
        var rows: [JSONOutlineRow] = []
        appendVisible(items, collapsed: collapsed, depth: 0, into: &rows)
        return rows
    }

    /// Every id in the tree, depth-first.
    public static func allIDs(_ items: [ContentOutlineItem]) -> Set<String> {
        var ids: Set<String> = []
        insertIDs(items, into: &ids)
        return ids
    }

    /// Finds the item with `id` anywhere in the tree.
    public static func item(withID id: String, in items: [ContentOutlineItem]) -> ContentOutlineItem? {
        for entry in items {
            if entry.id == id {
                return entry
            }
            if let found = item(withID: id, in: entry.children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Building

    private static func rootTitle(_ node: JSONNode) -> String {
        switch node.value {
        case .object: String(localized: "Object", bundle: .module)
        case .array: String(localized: "Array", bundle: .module)
        default: scalarTitle(node)
        }
    }

    private static func scalarTitle(_ node: JSONNode) -> String {
        switch node.value {
        case let .string(value): value
        case let .number(raw): raw
        case let .boolean(value): value ? "true" : "false"
        case .null: "null"
        case .object, .array: ""
        }
    }

    private static func build(_ node: JSONNode, path: String, title: String, depth: Int) -> ContentOutlineItem {
        let children: [ContentOutlineItem] = switch node.value {
        case let .object(members):
            members.map { member in
                build(
                    member.value,
                    path: "\(path).\(member.key)",
                    title: memberTitle(member),
                    depth: depth + 1
                )
            }
        case let .array(elements):
            elements.enumerated().map { index, element in
                build(
                    element,
                    path: "\(path)[\(index)]",
                    title: elementTitle(element, index: index),
                    depth: depth + 1
                )
            }
        case .string, .number, .boolean, .null:
            []
        }
        return ContentOutlineItem(
            id: path,
            title: title,
            lineRange: node.lineRange,
            sourceRange: node.sourceRange,
            children: children
        )
    }

    /// The outline label for an object member: the key alone for a non-empty
    /// container, `key { }` / `key [ ]` for an empty one, the scalar value
    /// otherwise.
    private static func memberTitle(_ member: JSONObjectMember) -> String {
        switch member.value.value {
        case .object where !objectIsEmpty(member.value):
            member.key
        case .object:
            "\(member.key) { }"
        case .array where !arrayIsEmpty(member.value):
            member.key
        case .array:
            "\(member.key) [ ]"
        default:
            scalarTitle(member.value)
        }
    }

    /// The outline label for an array element: `[index]` for a non-empty
    /// container, `[index] { }` / `[index] [ ]` for an empty one, the scalar
    /// value otherwise.
    private static func elementTitle(_ element: JSONNode, index: Int) -> String {
        switch element.value {
        case .object where !objectIsEmpty(element):
            "[\(index)]"
        case .object:
            "[\(index)] { }"
        case .array where !arrayIsEmpty(element):
            "[\(index)]"
        case .array:
            "[\(index)] [ ]"
        default:
            scalarTitle(element)
        }
    }

    private static func objectIsEmpty(_ node: JSONNode) -> Bool {
        if case let .object(members) = node.value {
            return members.isEmpty
        }
        return false
    }

    private static func arrayIsEmpty(_ node: JSONNode) -> Bool {
        if case let .array(elements) = node.value {
            return elements.isEmpty
        }
        return false
    }

    // MARK: - Rows

    private static func appendVisible(
        _ items: [ContentOutlineItem],
        collapsed: Set<String>,
        depth: Int,
        into rows: inout [JSONOutlineRow]
    ) {
        for item in items {
            rows.append(JSONOutlineRow(item: item, depth: depth))
            if !collapsed.contains(item.id) {
                appendVisible(item.children, collapsed: collapsed, depth: depth + 1, into: &rows)
            }
        }
    }

    private static func insertIDs(_ items: [ContentOutlineItem], into ids: inout Set<String>) {
        for item in items {
            ids.insert(item.id)
            insertIDs(item.children, into: &ids)
        }
    }
}

/// One rendered outline row: an item plus its tree depth.
public struct JSONOutlineRow: Sendable, Equatable, Identifiable {
    public let item: ContentOutlineItem
    public let depth: Int

    public var id: String {
        item.id
    }

    public init(item: ContentOutlineItem, depth: Int) {
        self.item = item
        self.depth = depth
    }
}
