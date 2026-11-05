import LegacyMath
import Testing

@Suite("New grammar contract against unchanged production scanner")
struct GrammarContractTests {
    @Test func currencyDoesNotConsumeLaterMath() {
        #expect(MathSpanScanner.scan("$5 and $10; then $x$").map(\.latex) == ["x"])
    }
    @Test func evenBackslashesDoNotEscapeTheOpeningDollar() {
        #expect(MathSpanScanner.scan(#"\\$x$"#).map(\.latex) == ["x"])
    }
    @Test func aDigitAfterTheClosingDollarKeepsTheCandidateLiteral() {
        #expect(MathSpanScanner.scan("$x$2").isEmpty)
    }
    @Test func whitespaceCannotOpenInlineMath() {
        #expect(MathSpanScanner.scan("$ x$").isEmpty)
    }
}
