import Foundation
import Markdown

func describe(_ node: any Markup) -> [String: Any] {
    var value: [String: Any] = ["type": String(describing: type(of: node))]
    if let range = node.range {
        value["start"] = [range.lowerBound.line, range.lowerBound.column]
        value["end"] = [range.upperBound.line, range.upperBound.column]
    }
    if let link = node as? Link {
        value["destination"] = link.destination
        value["title"] = link.title
        value["isAutolinkHeuristic"] = link.isAutolink
    }
    if let text = node as? Markdown.Text { value["text"] = text.string }
    if let code = node as? InlineCode { value["code"] = code.code }
    if let code = node as? CodeBlock { value["code"] = code.code }
    value["children"] = node.children.map(describe)
    return value
}

var results: [[String: Any]] = []
for ending in ["\n", "\r\n", "\r"] {
    let inputs = [
        "> before" + ending + "lazy $x$",
        "> before" + ending + ">     $x$",
        "- before" + ending + "    $x$",
        "> - before" + ending + ">      $x$",
        "> $a$" + ending + "> $b$",

        "before" + ending + "| A | B |" + ending + "|---|---|" + ending + "| $x$ | $y$ |",
        "漢😀 before [$x$][]" + ending + ending + "[$x$]: /target \"title\"",
        "> - before $$x % comment" + ending + ">   +y$$ after",
        "> - ```tex" + ending + ">   $literal$" + ending + ">   ```",
        "`$literal$` then $x$ and <span title='$attribute$'>$y$</span>",
        "[a \\] $x$][]" + ending + ending + "[a \\] $x$]: /target",
        "| A | B |" + ending + "|---|---|" + ending + "| $x$ | $y$ |",
        "![image $literal$](/image.png) [www.example.com](www.example.com)",
        "\t$x$",
        ">\t$x$",
        "-\t$x$ and [$y$](/target)",
        "$[x](y)$ and [$z$](/target)",
        "[**$x$**][]" + ending + ending + "[**$x$**]: /target",

    ]
    let extra: [String] = CommandLine.arguments.count > 1
        ? try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) : []
    for source in inputs + extra.map({ $0.replacingOccurrences(of: "\n", with: ending) }) {
        let document = Document(parsing: source)
        results.append(["source": source, "tree": describe(document), "formatted": document.format()])
    }
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(data)
