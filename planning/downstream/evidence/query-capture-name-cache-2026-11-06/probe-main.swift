import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownResources

func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}
let text = Fixtures.markdownRepeating(line: "# Heading\n\nSome `code` and **bold** text.\n\n", totalBytes: 1_000_000)
let language = Language(tree_sitter_markdown())
guard let url = TreeSitterMarkdownResources.queriesURL else { fatalError("Missing actual query resource") }
let query = try Query(language: language, data: Data(contentsOf: url.appendingPathComponent("highlights.scm")))
let count = Int(CommandLine.arguments.dropFirst().first ?? "5") ?? 5
for index in 0..<count {
    let began = ContinuousClock.now
    let parser = Parser()
    try parser.setLanguage(language)
    guard let tree = parser.parse(text), let root = tree.rootNode else { fatalError("Actual parse failed") }
    let parsed = ContinuousClock.now
    let cursor = query.execute(node: root, in: tree)
    cursor.setRange(NSRange(location: 0, length: (text as NSString).length))
    let highlights = cursor.highlights()
    let finished = ContinuousClock.now
    if let destination = CommandLine.arguments.dropFirst(2).first {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(highlights).write(to: URL(fileURLWithPath: destination))
    }
    precondition(!root.hasError && !highlights.isEmpty)
    let record: [String: Any] = ["iteration": index, "utf8_bytes": text.utf8.count,
        "utf16_units": text.utf16.count, "captures": highlights.count,
        "parse_seconds": seconds(began.duration(to: parsed)),
        "query_seconds": seconds(parsed.duration(to: finished)),
        "total_seconds": seconds(began.duration(to: finished))]
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

let controlText = "# First e\u{301} 😀\n\nBody with a second paragraph.\n\n# Last\n"
let controlParser = Parser()
try controlParser.setLanguage(language)
guard let controlTree = controlParser.parse(controlText) else { fatalError("Missing control tree") }
let controlQuery = try Query(language: language, data: Data("""
((atx_heading) @markup.heading
  (#set! @markup.heading role "first")
  (#set! @markup.heading role "last")
  (#set! global "match"))
((paragraph) @text.body (#set! @text.body role "body"))
""".utf8))
guard let controlSnapshot = controlTree.copy() else { fatalError("Missing immutable control snapshot") }
var headings = 0
var paragraphs = 0
for match in controlQuery.execute(in: controlSnapshot, depth: 3) {
    for capture in match.captures {
        precondition(capture.depth == 3)
        if capture.nameComponents == ["markup", "heading"] {
            precondition(capture.metadata == ["role": "last"])
            precondition(match.metadata == ["global": "match"])
            headings += 1
        } else {
            precondition(capture.nameComponents == ["text", "body"])
            precondition(capture.metadata == ["role": "body"])
            precondition(match.metadata.isEmpty)
            paragraphs += 1
        }
    }
}
precondition(headings == 2 && paragraphs == 1)
print("{\"metadata_controls\":true}")

let markerQuery = try Query(language: language, data: Data("(atx_h1_marker) @punctuation.heading.marker".utf8))
for prefix in ["body", "😀 e\u{301}", "first\r\nsecond\r\n"] {
    let before = prefix + "\r\n\r\n"
    guard let tree = controlParser.parse(before + "# Heading\r\n") else { fatalError("Missing range control") }
    let captures = markerQuery.execute(in: tree).flatMap(\.captures)
    precondition(captures.count == 1)
    precondition(captures[0].range == NSRange(location: before.utf16.count, length: 1))
    precondition(captures[0].nameComponents == ["punctuation", "heading", "marker"])
}
let aliasQuery = try Query(language: language, data: Data("""
((atx_heading (atx_h1_marker) @punctuation.heading) @heading.text
 (#set! @heading.text role "first") (#set! @heading.text role "last")
 (#set! @punctuation.heading role "marker") (#set! global "match"))
""".utf8))
let aliasMatches = Array(aliasQuery.execute(in: controlSnapshot, depth: 3))
precondition(aliasMatches.count == 2)
for match in aliasMatches {
    precondition(match.metadata == ["global": "match"] && match.captures.count == 2)
    for capture in match.captures {
        precondition(capture.depth == 3 && capture.name == aliasQuery.captureName(for: capture.index))
        if capture.nameComponents == ["heading", "text"] { precondition(capture.metadata == ["role": "last"]) }
        else { precondition(capture.nameComponents == ["punctuation", "heading"] && capture.metadata == ["role": "marker"]) }
    }
}
func checkIndependentCursors(query: Query, tree: Tree) async {
    let expected = query.execute(in: tree, depth: 2).highlights()
    precondition(!expected.isEmpty)
    await withTaskGroup(of: [NamedRange].self) { group in
        for _ in 0..<64 { group.addTask { query.execute(in: tree, depth: 2).highlights() } }
        for await observed in group { precondition(observed == expected) }
    }
}
await checkIndependentCursors(query: markerQuery, tree: controlSnapshot)
print("{\"range_alias_concurrent_controls\":true}")
