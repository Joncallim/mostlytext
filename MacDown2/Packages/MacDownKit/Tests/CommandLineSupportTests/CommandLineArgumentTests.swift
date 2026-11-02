import CommandBridge
import CommandLineSupport
import Foundation
import Testing

struct CommandLineArgumentTests {
    private func open(_ arguments: [String]) throws -> CommandLineOpenArguments {
        guard case let .open(value) = CommandLineArguments.parse(arguments) else {
            Issue.record("Expected open arguments"); throw CommandProtocolError.invalidState
        }
        return value
    }

    @Test func defaultExplicitOpenAndFlagsKeepStructuredPaths() throws {
        let paths = ["space file.md", "漢\n$().md", "link/../other"]
        for prefix in [[], ["open"]] {
            let parsed = try open(prefix + ["--wait"] + paths)
            #expect(parsed.wait && parsed.files == paths)
            let input = try parsed.inputPlan(workingDirectory: "/caller", stdinIsTerminal: false)
            #expect(input.paths == paths.map { "/caller/" + $0 })
            #expect(!input.readsStdin)
        }
    }

    @Test func escapesKeepDashAndReservedCommandFilenames() throws {
        #expect(try open(["--", "--wait", "formats", "open"]).files == ["--wait", "formats", "open"])
        #expect(try open(["open", "--", "-name"]).files == ["-name"])
    }

    @Test func bareInteractiveBarePipeAndExplicitStdinAreDifferent() throws {
        let bare = try open([])
        #expect(try !bare.inputPlan(workingDirectory: "/caller", stdinIsTerminal: true).readsStdin)
        #expect(try bare.inputPlan(workingDirectory: "/caller", stdinIsTerminal: false).readsStdin)
        let explicit = try open(["--wait", "one.md", "-"])
        let plan = try explicit.inputPlan(workingDirectory: "/caller", stdinIsTerminal: true)
        #expect(plan.readsStdin && plan.paths == ["/caller/one.md"])
        let request = try plan.request(stdin: Data())
        #expect(request.stdin?.byteCount == 0)
        #expect(throws: CommandProtocolError.invalidStdinDescriptor) { try plan.request(stdin: nil) }
    }

    @Test func helpVersionAndFormatsParseWithoutAnyIO() {
        #expect(CommandLineArguments.parse(["formats"]) == .formats)
        #expect(CommandLineArguments.parse(["--version"]) == .version)
        for args in [["--help"], ["open", "--help"], ["formats", "--help"]] {
            guard case let .display(text, code) = CommandLineArguments.parse(args) else {
                Issue.record("Expected help output"); continue
            }
            #expect(code == 0 && text.contains("USAGE"))
        }
    }

    @Test func invalidArgumentsReturnUsageExitBeforeInput() {
        for args in [
            ["--unknown"], ["file", "--unknown"], ["-", "-"], ["formats", "extra"], ["--version", "file"],
            Array(repeating: "file", count: 33),
        ] {
            guard case let .display(text, code) = CommandLineArguments.parse(args) else {
                Issue.record("Expected usage failure"); continue
            }
            #expect(code == 2 && !text.isEmpty)
        }
    }
}
