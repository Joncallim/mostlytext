import Testing
@testable import SwiftUIMath
struct TruncatedArgumentTests {
  @Test func mismatchedRadicalDegreeIsSafe() {
    var parser = Math.Parser(string: #"\sqrt[}"#)
    let result = parser.build()
    #expect(result == nil)
    #expect(parser.error?.code == .mismatchedBraces)
  }

  @Test func incompleteContinuedFractionIsSafe() {
    var parser = Math.Parser(string: #"\cfrac["#)
    let result = parser.build()
    #expect(result == nil)
    #expect(parser.error?.code == .characterNotFound)
  }
}
