import Foundation
import Textual

struct MathAdapterProbeSample: Sendable, CustomStringConvertible {
    let name: String
    let source: String
    let token: String
    let latex: String
    let style: AnyAttachment.MathStyle
    let count: Int
    let repairReferences: Bool
    let expected: String?
    let hasLink: Bool

    var description: String {
        name
    }

    init(_ name: String, _ source: String, token: String = "$x$", latex: String = "x",
         style: AnyAttachment.MathStyle = .inline, count: Int = 1, repairReferences: Bool = false,
         expected: String? = nil, hasLink: Bool = false) {
        self.name = name
        self.source = source
        self.token = token
        self.latex = latex
        self.style = style
        self.count = count
        self.repairReferences = repairReferences
        self.expected = expected
        self.hasLink = hasLink
    }

    static let all: [Self] = [
        .init("escaped dollar", #"Price \$5; real $x$."#, expected: "Price $5; real \u{FFFC}."),
        .init("Markdown punctuation", #"$a_b * c \alpha$"#, token: #"$a_b * c \alpha$"#,
              latex: #"a_b * c \alpha"#, expected: "\u{FFFC}"),
        .init("emphasis", "*Before $x$ after*", expected: "Before \u{FFFC} after"),
        .init("inline link", "[$x$](/target \"title\")", expected: "\u{FFFC}", hasLink: true),
        .init("full reference", "[$x$][math]\n\n[math]: /target \"title\"", expected: "\u{FFFC}", hasLink: true),
        .init("collapsed reference", "[$x$][]\n\n[$x$]: /target \"title\"", repairReferences: true,
              expected: "\u{FFFC}", hasLink: true),
        .init("shortcut reference", "[$x$]\n\n[$x$]: /target \"title\"", repairReferences: true,
              expected: "\u{FFFC}", hasLink: true),
        .init("shared definition", "[label $x$][] and [label $x$][]\n\n[label $x$]: /target \"same\"",
              count: 2, repairReferences: true, expected: "label \u{FFFC} and label \u{FFFC}", hasLink: true),
        .init("formatted reference key", "[**$x$**][]\n\n[**$x$**]: /target \"title\"",
              repairReferences: true, expected: "\u{FFFC}", hasLink: true),
        .init("literal code", "`$literal$` plus $x$", expected: "$literal$ plus \u{FFFC}"),
        .init("currency admission fixture", "$5 and $10; then $x$", expected: "$5 and $10; then \u{FFFC}"),
        .init("duplicate expressions", "one $x$ then $x$", count: 2, expected: "one \u{FFFC} then \u{FFFC}"),
        .init("Unicode and CRLF", "漢😀 before $x$.\r\n\r\nAfter."),
        .init("multiline percent comment", "Before.\n\n$$x % comment\n+y$$\n\nAfter.",
              token: "$$x % comment\n+y$$", latex: "x % comment\n+y", style: .display),
    ]

    func spans() throws -> [MathAdapterProbe.Span] {
        let text = source as NSString
        var cursor = 0
        return try (0 ..< count).map { _ in
            let range = text.range(of: token, range: NSRange(location: cursor, length: text.length - cursor))
            guard range.location != NSNotFound else { throw MathAdapterProbe.Failure.invalidInput }
            cursor = range.upperBound
            return MathAdapterProbe.Span(range: range, latex: latex, style: style, identifier: UUID())
        }
    }

    func references(for spans: [MathAdapterProbe.Span]) throws -> [MathAdapterProbe.Reference] {
        guard repairReferences else { return [] }
        let text = source as NSString
        var seen = Set<NSRange>()
        return try spans.compactMap { span in
            let opening = text.range(
                of: "[",
                options: .backwards,
                range: NSRange(location: 0, length: span.range.location)
            )
            let closing = text.range(of: "]", range: NSRange(location: span.range.upperBound,
                                                             length: text.length - span.range.upperBound))
            guard opening.location != NSNotFound, closing.location != NSNotFound
            else { throw MathAdapterProbe.Failure.invalidInput }
            let label = NSRange(location: opening.location + 1, length: closing.location - opening.location - 1)
            guard seen.insert(label).inserted else { return nil }
            let suffixStart = closing.upperBound
            let collapsed = suffixStart + 2 <= text.length && text.substring(with: NSRange(
                location: suffixStart,
                length: 2
            )) == "[]"
            return MathAdapterProbe.Reference(
                label: label,
                suffix: NSRange(location: suffixStart, length: collapsed ? 2 : 0)
            )
        }
    }
}
