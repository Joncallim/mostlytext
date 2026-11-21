import Foundation
@testable import Highlighting
import Testing

@MainActor
struct MarkdownSectionCacheLookupTests {
    @Test func paragraphLookupDoesNotCrossAChildSectionOrUnicodeBoundary() throws {
        let source = "# Top\n\ncafé 😊 direct words\n\n## Child\n\nchild words\n"
        let snapshot = try MarkdownSectionParser.snapshot(source: source, registry: GrammarRegistry())
        let parent = try #require(snapshot.rootSnapshot.tree.rootNode?.child(at: 0))
        let text = source as NSString
        let direct = text.range(of: "direct words")
        let child = text.range(of: "child words")
        let heading = text.range(of: "Top")
        try #require(direct.location != NSNotFound && child.location != NSNotFound
            && heading.location != NSNotFound)
        #expect(MarkdownSectionCache.paragraph(
            in: parent, overlapping: NSRange(location: direct.location + 2, length: 0)
        )?.nodeType == "paragraph")
        #expect(MarkdownSectionCache.paragraph(in: parent, overlapping: heading) == nil)
        #expect(MarkdownSectionCache.paragraph(in: parent, overlapping: child) == nil)
        #expect(MarkdownSectionCache.paragraph(in: parent, overlapping: NSRange(
            location: direct.location, length: NSMaxRange(child) - direct.location
        )) == nil)
    }
}
