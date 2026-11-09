import Foundation

/// One user- or app-defined snippet. Plain data: a name to show, a body in the
/// `SnippetTemplate` grammar, and the format ids it applies to.
public struct Snippet: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity. A user snippet with the same id as a built-in replaces it.
    public var id: String
    public var name: String
    public var body: String
    /// `FileFormat.id`s this snippet is offered for. Empty means every format.
    public var scopes: [String]

    public init(id: String, name: String, body: String, scopes: [String] = []) {
        self.id = id
        self.name = name
        self.body = body
        self.scopes = scopes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, body, scopes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        body = try container.decode(String.self, forKey: .body)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
    }

    public func applies(toFormatID formatID: String) -> Bool {
        scopes.isEmpty || scopes.contains(formatID)
    }

    var isUsable: Bool {
        !id.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The on-disk snippet file: `{ "version": 1, "snippets": [ … ] }`.
///
/// Decoding is lossy per element: one hand-edited snippet that is malformed
/// (missing a field, wrong type) is skipped and counted, never taking the
/// user's other snippets down with it.
public struct SnippetLibrary: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var snippets: [Snippet]
    /// Entries present in the file but skipped as malformed. Not persisted.
    public private(set) var skippedCount = 0

    public init(snippets: [Snippet] = []) {
        version = Self.currentVersion
        self.snippets = snippets
    }

    private enum CodingKeys: String, CodingKey {
        case version, snippets
    }

    private struct Lossy: Decodable {
        let snippet: Snippet?

        init(from decoder: any Decoder) throws {
            snippet = try? Snippet(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let entries = try container.decodeIfPresent([Lossy].self, forKey: .snippets) ?? []
        let decoded = entries.compactMap(\.snippet).filter(\.isUsable)
        snippets = decoded
        skippedCount = entries.count - decoded.count
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(snippets, forKey: .snippets)
    }
}

/// Merges the built-in snippets with the user's and filters to a format.
public enum SnippetCatalog {
    /// Built-ins first, then user snippets; a user snippet whose id matches an
    /// earlier one replaces it in place. Filtered to `formatID`, sorted by name.
    public static func snippets(
        user: [Snippet],
        formatID: String,
        builtIn: [Snippet] = BuiltInSnippets.all
    ) -> [Snippet] {
        var byID: [String: Snippet] = [:]
        var order: [String] = []
        for snippet in builtIn + user where snippet.isUsable {
            if byID.updateValue(snippet, forKey: snippet.id) == nil {
                order.append(snippet.id)
            }
        }
        return order
            .compactMap { byID[$0] }
            .filter { $0.applies(toFormatID: formatID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Case-insensitive substring match on the name; empty query keeps all.
    public static func filter(_ snippets: [Snippet], query: String) -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snippets }
        return snippets.filter { $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

public enum BuiltInSnippets {
    /// Resolve display names when the picker opens. IDs and insertion bodies
    /// stay stable across languages and user overrides keep their own names.
    public static var all: [Snippet] {
        all(in: .module)
    }

    static func all(in bundle: Bundle) -> [Snippet] {
        [
            Snippet(
                id: "builtin.markdown.codeBlock",
                name: String(localized: "Fenced Code Block", bundle: bundle),
                body: "```\n${selection}$0\n```",
                scopes: ["markdown"]
            ),
            Snippet(id: "builtin.markdown.link", name: String(localized: "Link", bundle: bundle),
                    body: "[${selection}]($0)", scopes: ["markdown"]),
            Snippet(
                id: "builtin.markdown.linkFromClipboard",
                name: String(localized: "Link from Clipboard", bundle: bundle),
                body: "[${selection}](${clipboard})$0",
                scopes: ["markdown"]
            ),
            Snippet(id: "builtin.markdown.image", name: String(localized: "Image", bundle: bundle),
                    body: "![${selection}]($0)", scopes: ["markdown"]),
            Snippet(
                id: "builtin.markdown.table",
                name: String(localized: "Table", bundle: bundle),
                body: "| Column | Column |\n| ------ | ------ |\n| $0 |  |",
                scopes: ["markdown"]
            ),
            Snippet(id: "builtin.markdown.task", name: String(localized: "Task", bundle: bundle),
                    body: "- [ ] ${selection}$0", scopes: ["markdown"]),
        ]
    }
}
