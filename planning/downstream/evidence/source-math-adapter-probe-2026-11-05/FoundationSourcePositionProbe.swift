import Foundation

let marker = "MTMATH0123456789ABCDEFZ0Q"
let inputs = [
    "Before \(marker) after.",
    "漢😀 before *\(marker)* after.",
    "[\(marker)](/target \"title\")",
    "[\(marker)][]\n\n[$x$]: /target \"title\"",
    "[\(marker)][$x$]\n\n[$x$]: /target \"title\"",
    "MT**MATH0123456789ABCDEF**Z0Q",
    "MTMATH0123456789ABCDEFZ0Q and `MTMATH0123456789ABCDEFZ0Q`",
    "Before &#77;TMATH0123456789ABCDEFZ0Q after."
]
var output: [[String: Any]] = []
for input in inputs {
    let parsed = try AttributedString(markdown: input, options: .init(appliesSourcePositionAttributes: true))
    let runs = parsed.runs.map { run -> [String: Any] in
        var item: [String: Any] = ["text": String(parsed[run.range].characters)]
        if let link = run.link { item["link"] = link.absoluteString }
        if let position = run.markdownSourcePosition, let range = Range(position, in: input) {
            item["source_utf16"] = [range.lowerBound.utf16Offset(in: input), range.upperBound.utf16Offset(in: input)]
            item["source"] = String(input[range])
        }
        return item
    }
    output.append(["source": input, "rendered": String(parsed.characters), "runs": runs])
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(data)
