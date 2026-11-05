import Foundation
import Testing

@testable import SwiftUIMath

struct ValidatedBodyTests {
  private let limits = Math.BodyLimits(
    maximumUTF16Length: 16_384, maximumDepth: 64, maximumParserSteps: 65_536
  )

  private func body(_ source: String, limits custom: Math.BodyLimits? = nil) throws
    -> Math.ValidatedBody
  {
    let result = try Math.validateBody(source, limits: custom ?? limits)
    guard case .valid(let value) = result else {
      Issue.record("Expected a validated body: \(source)")
      throw Math.BodyConfigurationError.invalidLimits
    }
    return value
  }

  @Test func successfulValidationPreservesExactAuthoredBytesAndLimits() throws {
    let source = "x% comment🙂\r\n+y"
    let value = try body(source)
    #expect(Array(value.source.utf8) == Array(source.utf8))
    #expect(value.limits == limits)
  }

  @Test func failuresRetainTheirExistingCategoryAndSourceCursor() throws {
    guard case .invalid(let diagnostic) = try Math.validateBody(#"\sqrt[}"#, limits: limits) else {
      Issue.record("Expected malformed body")
      return
    }
    #expect(diagnostic.error.code == .mismatchedBraces)
    #expect(diagnostic.utf16Offset == 7)
    let small = Math.BodyLimits(maximumUTF16Length: 1, maximumDepth: 1, maximumParserSteps: 1)
    guard case .resourceLimit(.inputLength) = try Math.validateBody("xy", limits: small) else {
      Issue.record("Expected input resource limit")
      return
    }
    #expect(throws: Math.BodyConfigurationError.invalidLimits) {
      try Math.validateBody(
        "x", limits: .init(maximumUTF16Length: 0, maximumDepth: 1, maximumParserSteps: 1))
    }
  }

  @Test func tokenAndInputIdentityUseExactUTF8InsteadOfCanonicalStringEquality() throws {
    let composed = "\\text{é}"
    let decomposed = "\\text{e\u{301}}"
    #expect(composed == decomposed)
    let first = try body(composed)
    let second = try body(decomposed)
    #expect(first != second)
    #expect(Set([first, second]).count == 2)
    #expect(Set([Math.RenderInput.automatic(composed), .automatic(decomposed)]).count == 2)
    let repeated = try body(composed)
    #expect(first == repeated)
    #expect(Set([first, repeated]).count == 1)
  }

  @Test func limitsAndParsingModeArePartOfRenderIdentity() throws {
    let value = try body("$x$")
    let narrower = try body(
      "$x$", limits: .init(maximumUTF16Length: 1_024, maximumDepth: 8, maximumParserSteps: 256))
    #expect(value != narrower)
    let automatic = Math.RenderInput.automatic(value.source)
    let raw = Math.RenderInput.body(value)
    #expect(automatic != raw)
    #expect(Set([automatic, raw, .body(narrower)]).count == 3)
    let automaticList = try #require(automatic.parsedAtomList())
    let rawList = try #require(raw.parsedAtomList())
    #expect(automaticList.atoms.first?.type == .style)
    #expect(rawList.atoms.first?.type != .style)
  }

  @Test func bodyModeRetainsCommentAndDelimiterSemanticsOnEveryReparse() throws {
    let input = try Math.RenderInput.body(body("x% ignored\r\n+y"))
    for _ in 0..<3 {
      #expect(Math.Parser.atomListToString(input.parsedAtomList()) == "x+y")
    }
  }

  @Test func cancellationPreventsValidationAndColdBodyReparse() async throws {
    let value = try body("x+y")
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      #expect(Math.RenderInput.body(value).isCancelled)
      #expect(Math.RenderInput.body(value).parsedAtomList() == nil)
      do {
        _ = try Math.validateBody("{x", limits: limits)
        Issue.record("Cancelled validation succeeded")
      } catch is CancellationError {} catch {
        Issue.record("Unexpected cancellation error: \(error)")
      }
    }
    await task.value
  }

  @Test func cacheEvictionReleasesDisposableValuesAndAllowsRecomputation() {
    final class Payload {}
    var cache = BoundedRenderCache<Int, Payload>(capacity: 2)
    weak var first: Payload?
    do {
      let value = Payload()
      first = value
      cache.insert(value, for: 1)
    }
    cache.insert(Payload(), for: 2)
    #expect(first != nil)
    cache.insert(Payload(), for: 3)
    #expect(first == nil)
    #expect(cache.value(for: 1) == nil)
    #expect(cache.value(for: 3) != nil)
    #expect(cache.count <= 2)
    cache.insert(Payload(), for: 1)
    #expect(cache.value(for: 1) != nil)
    #expect(cache.count <= 2)
  }

  @Test func replacingAnExistingCacheKeyDoesNotEvictOtherEntries() {
    var cache = BoundedRenderCache<Int, Int>(capacity: 2)
    cache.insert(1, for: 1)
    cache.insert(2, for: 2)
    cache.insert(3, for: 1)
    #expect(cache.value(for: 1) == 3)
    #expect(cache.value(for: 2) == 2)
    #expect(cache.count == 2)
    for number in 0..<10_000 {
      cache.insert(number, for: number)
      #expect(cache.count <= 2)
      #expect(cache.value(for: number) == number)
    }
  }
}
