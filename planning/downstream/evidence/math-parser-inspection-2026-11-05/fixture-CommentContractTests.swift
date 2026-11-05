import Foundation
import Testing
@testable import SwiftUIMath

struct CommentContractTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func aPercentCommentDoesNotBecomeMathAtoms(ending: String) throws {
        var parser = Math.Parser(string: "x % ignored" + ending + "+y")
        let built = parser.build()
        let result = try #require(built)
        #expect(parser.error == nil)
        #expect(Math.Parser.atomListToString(result) == "x+y")
    }

    @Test func originalStructuredErrorCodeIsAvailable() {
        var parser = Math.Parser(string: #"\notARealCommand{x}"#)
        let result = parser.build()
        #expect(result == nil)
        #expect(parser.error?.code == .invalidCommand)
    }
}
