import Foundation
import Markdown
import Preview
import Testing

struct ReferenceReplayTests {
    private struct Target: Equatable {
        let destination: Data
        let title: Data?
    }
    private func targets(_ node: any Markup) -> [Target] {
        if let link = node as? Link, let destination = link.destination {
            return [Target(destination: Data(destination.utf8), title: link.title.map { Data($0.utf8) })]
        }
        return node.children.flatMap(targets)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func originalResolvedTargetsSurviveDefinitionReplay(_ ending: String) throws {
        let cases = [
            ("single line", "[key]: /right \"title\"\n\n[visible][key]", "[visible][key]"),
            ("fenced fake", "```\n[key]: /wrong \"fake\"\n```\n\n[key]: /right \"title\"\n\n[visible][key]", "[visible][key]"),
            ("multiline", "[key]:\n  /right\n  \"title\"\n\n[visible][key]", "[visible][key]"),
            ("escaped bracket", "[a\\]b]: /right \"title\"\n\n[visible][a\\]b]", "[visible][a\\]b]"),
            ("quote", "> [key]: /right\n> \"title\"\n\n[visible][key]", "[visible][key]"),
            ("list and quote", "> - [key]: /right\n>   \"title\"\n\n[visible][key]", "[visible][key]"),
        ]
        for (name, input, block) in cases {
            let source = input.replacingOccurrences(of: "\n", with: ending)
            let document = Document(parsing: source)
            let expected = targets(document)
            try #require(expected == [Target(destination: Data("/right".utf8), title: Data("title".utf8))], "Original real parser must establish target/title: \(name)")
            let definitions = PreviewLinkDefinitions.extract(from: source)
            let replay = PreviewLinkDefinitions.prefixed(block, with: definitions)
            #expect(targets(Document(parsing: replay)) == expected, "Real parser replay must preserve target/title: \(name)")
        }
    }
}
