import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes

@Suite("Export parse options")
struct ExportParseOptionsTests {
    @Test(arguments: ["@Note {\nbody\n}\n\n# After\n", "@Note {\nbody\n\n# After\n"])
    func directiveSyntaxExportsAsOrdinaryMarkdown(source: String) async throws {
        var bodies: [String] = []
        for enabled in [false, true] {
            let request = ExportRequest(
                text: source,
                sourceGeneration: 1,
                theme: BundledThemes.light,
                parseOptions: .init(blockDirectives: enabled)
            )
            let prepared = try await ExportService.prepare(
                request,
                target: .html(
                    url: URL(fileURLWithPath: "/tmp/directive-policy.html"),
                    mode: .standalone(style: .embedded)
                )
            )
            #expect(prepared.bodyHTML.contains("@Note {"))
            #expect(prepared.bodyHTML.contains("body"))
            #expect(prepared.bodyHTML.contains("After</h1>"))
            bodies.append(prepared.bodyHTML)
        }
        #expect(bodies[0] == bodies[1])
    }

    @Test func composerUsesTheOptionsFrozenIntoItsRequest() async throws {
        let source = "@Note {\nbody\n}\n"

        for enabled in [false, true] {
            let options = MarkdownParseOptions(blockDirectives: enabled)
            let parser = RecordingParseExecutor()
            let request = ExportRequest(
                text: source,
                sourceGeneration: enabled ? 2 : 1,
                theme: BundledThemes.light,
                parseOptions: options
            )

            _ = try await ExportService.prepare(
                request,
                target: .html(
                    url: URL(fileURLWithPath: "/tmp/export-options.html"),
                    mode: .standalone(style: .embedded)
                ),
                engine: parser
            )

            let calls = await parser.calls
            let call = try #require(calls.first)
            #expect(calls.count == 1)
            #expect(call.options == options)
            #expect(call.containsBlockDirective == enabled)
        }
    }
}

private actor RecordingParseExecutor: ParseExecuting {
    struct Call: Sendable {
        let options: MarkdownParseOptions
        let containsBlockDirective: Bool
    }

    private(set) var calls: [Call] = []

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        let document = try await ParseEngine().parse(text, options: options, revision: revision)
        calls.append(Call(
            options: options,
            containsBlockDirective: document.blocks.contains { $0.kind == .custom("BlockDirective") }
        ))
        return document
    }
}
