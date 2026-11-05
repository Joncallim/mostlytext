import Foundation
import MarkdownEngine
import Testing
struct TemporaryHTMLFactsProbe {
 @Test func probeHTMLLiteralOwnership() async throws {
  for source in ["<span>$x$</span>", "<span data-eq=\"$x$\">", "<div>\n$x$\n</div>"] {
   let document = try await ParseEngine().parse(source, revision: 1)
   let facts = try #require(document.sourceFacts)
   print("HTML_FACTS_PROBE", source.debugDescription, facts.literalRanges)
  }
 }
}
