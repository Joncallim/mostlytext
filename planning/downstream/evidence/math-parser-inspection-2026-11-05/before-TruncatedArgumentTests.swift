import Testing
@testable import SwiftUIMath
struct TruncatedArgumentTests {
  @Test func incompleteContinuedFractionIsSafe() {
    var parser = Math.Parser(string: #"\cfrac["#)
    let result = parser.build()
    #expect(result == nil)
    #expect(parser.error?.code == .characterNotFound)
  }
}
