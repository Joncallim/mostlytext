import Foundation
import Testing
@testable import SwiftUIMath

struct BodyInspectionTests {
  private let limits = Math.BodyLimits(
    maximumUTF16Length: 16_384, maximumDepth: 64, maximumParserSteps: 65_536
  )

  @Test(arguments: ["\n", "\r\n", "\r"])
  func commentsAreNotAtoms(ending: String) throws {
    for input in ["x % ignored" + ending + "+y", "x%}\\bad{$" + ending + "+y"] {
      var parser = Math.Parser(string: input)
      let built = parser.build()
      let list = try #require(built)
      #expect(parser.error == nil)
      #expect(Math.Parser.atomListToString(list) == "x+y")
    }
    var parser = Math.Parser(string: "\\text{a% removed" + ending + "b}")
    let built = parser.build()
    let list = try #require(built)
    #expect(Math.Parser.atomListToString(list) == #"\mathrm{ab}"#)
  }

  @Test func lexicalCommentRulesAndScalarNeighbors() throws {
    let cases: [(String, String)] = [
      ("a% EOF", "a"), ("a%", "a"), ("%all", ""),
      (#"a\%b"#, #"a\%b"#), (#"a\\%b"#, #"a\\"#),
      (#"a\\\%b"#, #"a\\\%b"#),
      ("a% first\r\n% second\n+b", "a+b"),
      ("a\u{0600}%\u{301}hidden\n+b", "a\u{0600}+b"),
      ("a%hidden\r\n\u{301}+b", "a\u{301}+b"),
      ("a\r\nb\rc\nd", "a\r\nb\rc\nd")
    ]
    for (source, expected) in cases {
      let value = try Math.CommentSource(source)
      #expect(Array(value.text.utf8) == Array(expected.utf8))
      #expect(value.originalLength == source.utf16.count)
      #expect(value.originalOffset(for: value.text.utf16.count) == source.utf16.count)
    }
  }

  @Test func inspectionAcceptsValidBodies() throws {
    for body in ["", "x+y", #"\frac{x}{y}"#, #"\text{中文🙂}"#,
                 #"\begin{matrix}a&b\\c&d\end{matrix}"#] {
      guard case .valid = try Math.inspectBody(body, limits: limits) else {
        Issue.record("Expected valid body: \(body)"); continue
      }
    }
  }

  @Test func inspectionReturnsExistingErrorCodes() throws {
    let cases: [(String, Math.ParserError.Code)] = [
      ("{x", .mismatchedBraces), ("x}", .mismatchedBraces),
      (#"\notARealCommand{x}"#, .invalidCommand),
      (#"\left"#, .missingDelimiter), (#"\left z x"#, .invalidDelimiter),
      (#"\left(x"#, .missingRight), (#"\right)"#, .missingLeft),
      (#"\begin{notAnEnvironment}x\end{notAnEnvironment}"#, .invalidEnvironment),
      (#"\end{matrix}"#, .missingBegin), (#"\begin{matrix}x"#, .missingEnd),
      (#"x\limits"#, .invalidLimits)
    ]
    for (body, code) in cases {
      guard case let .invalid(diagnostic) = try Math.inspectBody(body, limits: limits) else {
        Issue.record("Expected structured invalid body: \(body)"); continue
      }
      #expect(diagnostic.error.code == code)
      #expect(!diagnostic.error.message.isEmpty)
      #expect(diagnostic.utf16Offset >= 0 && diagnostic.utf16Offset <= body.utf16.count)
    }
  }

  @Test(arguments: ["\n", "\r\n", "\r"])
  func errorCursorUsesOriginalUTF16AfterComments(ending: String) throws {
    let body = "\\text{🙂é}% hidden🙂" + ending + #"\notARealCommand{x}"#
    guard case let .invalid(diagnostic) = try Math.inspectBody(body, limits: limits) else {
      Issue.record("Expected unknown-command diagnostic"); return
    }
    #expect(diagnostic.error.code == .invalidCommand)
    let expected = (body as NSString).range(of: "{x}", options: .literal).location
    #expect(diagnostic.utf16Offset == expected)
    let unclosed = "{x%comment🙂" + ending
    guard case let .invalid(end) = try Math.inspectBody(unclosed, limits: limits) else {
      Issue.record("Expected missing-brace diagnostic"); return
    }
    #expect(end.utf16Offset == unclosed.utf16.count)
  }

  @Test func commentOffsetMapHandlesRepeatedAndAdjacentRemovals() throws {
    let value = try Math.CommentSource("a%🙂\r\n%b\nc%tail")
    #expect(value.text == "ac")
    #expect(value.originalOffset(for: 0) == 0)
    #expect(value.originalOffset(for: 1) == 10)
    #expect(value.originalOffset(for: 2) == 17)
  }

  @Test func bodyModeDoesNotDetectDollarDelimiters() throws {
    var automatic = Math.Parser(string: "$x$")
    let autoList = automatic.build()
    var raw = Math.Parser(string: "$x$")
    let rawList = raw.build(detectsDelimiters: false)
    #expect(automatic.mode == .inline)
    #expect(raw.mode == .display)
    #expect(autoList?.atoms.first?.type == .style)
    #expect(rawList?.atoms.first?.type != .style)
    #expect(raw.string == "$x$")
  }

  @Test func inputLengthLimitIsUTF16AndInclusive() throws {
    let limits = Math.BodyLimits(maximumUTF16Length: 2, maximumDepth: 8, maximumParserSteps: 32)
    guard case .valid = try Math.inspectBody("xy", limits: limits) else {
      Issue.record("Inclusive input boundary rejected"); return
    }
    guard case .valid = try Math.inspectBody("🙂", limits: limits) else {
      Issue.record("UTF16 boundary rejected"); return
    }
    guard case .resourceLimit(.inputLength) = try Math.inspectBody("🙂x", limits: limits) else {
      Issue.record("Expected input resource limit"); return
    }
  }

  @Test func recursiveAndStepBudgetsAreDistinctFromMalformedInput() throws {
    let shallow = Math.BodyLimits(maximumUTF16Length: 16_384, maximumDepth: 4, maximumParserSteps: 65_536)
    guard case .valid = try Math.inspectBody("{{{x}}}", limits: shallow) else {
      Issue.record("Inclusive depth rejected"); return
    }
    for body in ["{{{{x}}}}", String(repeating: "{", count: 5_000) + "x"] {
      guard case .resourceLimit(.depth) = try Math.inspectBody(body, limits: shallow) else {
        Issue.record("Expected recursive depth limit"); continue
      }
    }
    let steps = Math.BodyLimits(maximumUTF16Length: 128, maximumDepth: 8, maximumParserSteps: 2)
    guard case .valid = try Math.inspectBody("xy", limits: steps) else {
      Issue.record("Inclusive step boundary rejected"); return
    }
    for body in ["xyz", #"\unknown"#] {
      guard case .resourceLimit(.parserSteps) = try Math.inspectBody(body, limits: steps) else {
        Issue.record("Expected parser work limit"); continue
      }
    }
  }

  @Test func configurationsAreValidatedBeforeParsing() throws {
    for values in [(0, 1, 1), (1_048_577, 1, 1), (1, 0, 1), (1, 129, 1), (1, 1, 0), (1, 1, 1_000_001)] {
      let limits = Math.BodyLimits(maximumUTF16Length: values.0, maximumDepth: values.1, maximumParserSteps: values.2)
      #expect(throws: Math.BodyConfigurationError.invalidLimits) {
        try Math.inspectBody("x", limits: limits)
      }
    }
  }

  @Test func cancellationIsNotMalformedMathOrResourceExhaustion() async {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try Math.inspectBody("{x", limits: limits)
        Issue.record("Cancelled inspection succeeded")
      } catch is CancellationError { }
      catch { Issue.record("Wrong cancellation error: \(error)") }
    }
    await task.value
  }
}
