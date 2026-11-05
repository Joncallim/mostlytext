import Foundation
import MathSyntax
import Testing

@Suite("Shared original-source delimiter grammar")
struct MathDelimiterGrammarTests {
    @Test func inlineAndDisplayUseOriginalRangesAndBodyBytes() throws {
        let source = "漢😀 $e\u{0301}+x$ and $$a_b * c\\alpha$$."
        let result = try MathSyntaxTestSupport.scan(source)
        try MathSyntaxTestSupport.expect(result, source: source, tokens: [
            .init("$e\u{0301}+x$", "e\u{0301}+x", .inline),
            .init(#"$$a_b * c\alpha$$"#, #"a_b * c\alpha"#, .display),
        ])
    }

    @Test func currencyRecoveryPreservesTheLaterEquation() throws {
        let source = "$5 and $10; then $x$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source,
                                         tokens: [.init("$x$", "x", .inline)])
        let numeric = "$5$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(numeric), source: numeric,
                                         tokens: [.init(numeric, "5", .inline)])
    }

    @Test(arguments: ["2", "٢", "𝟚"])
    func decimalDigitAfterTheCloserKeepsItLiteral(_ digit: String) throws {
        let source = "$x$" + digit + "; then $y$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source,
                                         tokens: [.init("$y$", "y", .inline)])
    }

    @Test(arguments: [" ", "\t", "\u{00A0}", "\u{2003}"])
    func whitespaceCannotOpenOrEndInlineMath(_ space: String) throws {
        #expect(try MathSyntaxTestSupport.scan("$" + space + "x$").spans.isEmpty)
        #expect(try MathSyntaxTestSupport.scan("$x" + space + "$").spans.isEmpty)
    }

    @Test(arguments: 0 ... 12)
    func completeBackslashRunParityControlsAnOpener(_ count: Int) throws {
        let source = String(repeating: "\\", count: count) + "$x$"
        let tokens: [MathSyntaxTestSupport.ExpectedToken] = count % 2 == 0 ? [.init("$x$", "x", .inline)] : []
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source, tokens: tokens)
    }

    @Test(arguments: 0 ... 12)
    func escapedCloserDoesNotConsumeTheLaterEquation(_ count: Int) throws {
        let slashes = String(repeating: "\\", count: count)
        let source = "$x" + slashes + "$ after; $y$"
        var tokens: [MathSyntaxTestSupport.ExpectedToken] = []
        if count % 2 == 0 {
            tokens.append(.init("$x" + slashes + "$", "x" + slashes, .inline))
        }
        tokens.append(.init("$y$", "y", .inline))
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source, tokens: tokens)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func multilineCommentsRemainExactAndBlankLinesStopDisplay(_ ending: String) throws {
        let token = "$$x % comment" + ending + "+y$$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(token), source: token,
                                         tokens: [.init(token, "x % comment" + ending + "+y", .display)])
        let broken = "$$x" + ending + " \t" + ending + "y$$ then $z$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(broken), source: broken,
                                         tokens: [.init("$z$", "z", .inline)])
        let inline = "$x" + ending + "y$ then $z$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(inline), source: inline,
                                         tokens: [.init("$z$", "z", .inline)])
    }

    @Test func unpairedDisplayRecoveryAndDollarRunsAreDeliberate() throws {
        let source = "$$unfinished; then $x$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source,
                                         tokens: [.init("$x$", "x", .inline)])
        #expect(try MathSyntaxTestSupport.scan("$$$$").spans.isEmpty)
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan("$$$$$"), source: "$$$$$",
                                         tokens: [.init("$$$$$", "$", .display)])
        let precedence = "$unfinished $$x$$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(precedence), source: precedence,
                                         tokens: [.init("$$x$$", "x", .display)])
    }

    @Test(arguments: 0 ... 12)
    func displayOpenersHonorCompleteBackslashParity(_ count: Int) throws {
        let source = String(repeating: "\\", count: count) + "$$x$$"
        let tokens: [MathSyntaxTestSupport.ExpectedToken] = count % 2 == 0 ? [.init("$$x$$", "x", .display)] : []
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source, tokens: tokens)
    }

    @Test func escapedDisplayClosersAndLaterBlocksKeepTheirOwnership() throws {
        let escaped = "$$x\\$$ tail $$y$$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(escaped), source: escaped,
                                         tokens: [.init("$$x\\$$ tail $$", "x\\$$ tail ", .display)])
        let laterBlock = "$$unclosed\n\n$$y$$"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(laterBlock), source: laterBlock,
                                         tokens: [.init("$$y$$", "y", .display)])
    }

    @Test func graphemeExtendersAndPrependScalarsDoNotHideDollars() throws {
        let source = "\u{0600}$x$\u{200C}ها and $e\u{0301}$\u{FE0F}"
        try MathSyntaxTestSupport.expect(MathSyntaxTestSupport.scan(source), source: source,
                                         tokens: [
                                             .init("$x$", "x", .inline),
                                             .init("$e\u{0301}$", "e\u{0301}", .inline),
                                         ])
    }
}
