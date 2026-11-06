import Foundation
import MarkdownEngine
@testable import Preview
import Testing

struct PreviewHeadingLinkTests {
    private let current = URL(fileURLWithPath: "/Users/me/notes/report.md")

    @Test func bareAndResolvedFragmentsNameTheSameVerifiedOriginalHeading() async throws {
        let index = try await index()
        let heading = try #require(index.headings.first)
        let resolver = PreviewLinkResolver(baseURL: current, headingIndex: index)
        let fragment = try #require(URL(string: "#caf%C3%A9"))
        #expect(PreviewLinkResolver.action(for: fragment, headingIndex: index) ==
            .internalHeading(heading, index.identity))
        #expect(PreviewLinkResolver.action(
            for: resolver.resolve(fragment),
            currentDocument: current,
            headingIndex: index
        ) ==
            .internalHeading(heading, index.identity))
    }

    @Test func fragmentMatchingKeepsExactUnicodeSpellingAndDecodesOnlyOnce() async throws {
        let index = try await index()
        #expect(try action("#cafe%CC%81", index: index) == .unresolvedInternal("cafe\u{301}"))
        #expect(try action("#caf%25C3%25A9", index: index) == .unresolvedInternal("caf%C3%A9"))
        let cjk = try #require(index.headings.last)
        #expect(try action("#%E6%9D%B1%E4%BA%AC", index: index) == .internalHeading(cjk, index.identity))
        #expect(try action("#", index: index) == .unresolvedInternal(""))
    }

    @Test func rawHTMLOnlyAndUnknownTargetsStayUnresolved() async throws {
        let index = try await index()
        #expect(try action("#raw", index: index) == .unresolvedInternal("raw"))
        #expect(try action("#unknown", index: index) == .unresolvedInternal("unknown"))
        let url = try #require(URL(string: "#caf%C3%A9"))
        #expect(PreviewLinkResolver.action(for: url) == .unresolvedInternal("café"))
    }

    @Test func aDifferentQueryOrAuthorityCannotBorrowTheCurrentIndex() async throws {
        let index = try await index()
        for value in [
            "file:///Users/me/notes/report.md?changed=1#caf%C3%A9",
            "file://other-host/Users/me/notes/report.md#caf%C3%A9",
            "file://user@/Users/me/notes/report.md#caf%C3%A9",
        ] {
            let url = try #require(URL(string: value))
            #expect(PreviewLinkResolver.action(for: url, currentDocument: current, headingIndex: index) == .ignore)
        }
        let queried = try #require(URL(string: "file:///Users/me/notes/report.md?edition=1"))
        let same = try #require(URL(string: "file:///Users/me/notes/report.md?edition=1#caf%C3%A9"))
        #expect(try PreviewLinkResolver.action(for: same, currentDocument: queried, headingIndex: index) ==
            .internalHeading(#require(index.headings.first), index.identity))
    }

    @Test func fullPathIdentityDoesNotTreatAnotherDirectoryOrBasenameAsCurrent() async throws {
        let index = try await index()
        for path in ["/Users/me/other/report.md", "/Users/me/notes/other.md"] {
            var components = URLComponents(url: URL(fileURLWithPath: path), resolvingAgainstBaseURL: false)
            components?.fragment = "café"
            let url = try #require(components?.url)
            #expect(PreviewLinkResolver.action(for: url, currentDocument: current, headingIndex: index) ==
                .openInApp(URL(fileURLWithPath: path)))
        }
    }

    @Test func unsafeAndControlFragmentsNeverBecomeNativeTargetsOrExternalOpens() async throws {
        let index = try await index()
        for value in ["#caf%C3%A9%00", "#%FF", "#%0A", "javascript:alert(1)#café", "data:text/html,x#café"] {
            #expect(try action(value, index: index) == .ignore)
        }
        #expect(try action("#%ZZ", index: index) == .unresolvedInternal("%ZZ"))
    }

    @Test func permittedExternalHandlersRemainIndependentOfAnEqualFragment() async throws {
        let index = try await index()
        #expect(try action("https://example.com/report.md#caf%C3%A9", index: index) == .open)
        #expect(try action("mailto:a@example.com#caf%C3%A9", index: index) == .open)
        let executable = try #require(URL(string: "file:///tmp/run.command#caf%C3%A9"))
        #expect(PreviewLinkResolver.action(for: executable, currentDocument: current, headingIndex: index) == .reveal)
    }

    private func index() async throws -> HeadingAnchorIndex {
        let source = "<div id=raw>Raw</div>\n\n# Café\n\n# 東京\n"
        let document = try await ParseEngine().parse(source, revision: 4)
        return try HeadingAnchorIndex(
            document: document, sourceText: source, documentID: "own", recoveryEpoch: UUID(),
            sourceGeneration: 4, reservedIDs: ["raw"]
        )
    }

    private func action(_ value: String, index: HeadingAnchorIndex) throws -> PreviewLinkResolver.LinkAction {
        let url = try #require(URL(string: value))
        return PreviewLinkResolver.action(for: url, currentDocument: current, headingIndex: index)
    }
}
