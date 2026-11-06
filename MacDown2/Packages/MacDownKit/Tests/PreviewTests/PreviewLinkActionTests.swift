import Foundation
@testable import Preview
import Testing

/// Review pass 1: a clicked Preview link went straight to Launch Services.
struct PreviewLinkActionTests {
    private func action(_ string: String) -> PreviewLinkResolver.LinkAction {
        guard let url = URL(string: string) else { return .ignore }
        return PreviewLinkResolver.action(for: url)
    }

    @Test func webAndMailLinksOpen() {
        #expect(action("https://example.com/a") == .open)
        #expect(action("HTTP://example.com") == .open)
        #expect(action("mailto:a@example.com") == .open)
    }

    @Test func localDocumentsOpenInTheAppButOtherLocalFilesOnlyRevealInFinder() {
        #expect(action("file:///Users/me/notes/other.md") ==
            .openInApp(URL(fileURLWithPath: "/Users/me/notes/other.md")))
        #expect(action("file:///Users/me/notes/plain.TXT") ==
            .openInApp(URL(fileURLWithPath: "/Users/me/notes/plain.TXT")))
        #expect(action("file:///Users/me/scripts/setup.command") == .reveal)
        #expect(action("file:///Applications/Foo.app") == .reveal)
        #expect(action("file:///Users/me/run.sh") == .reveal)
    }

    @Test func everyOtherSchemeIsIgnored() {
        for link in [
            "ssh://host",
            "vnc://host",
            "smb://host/share",
            "x-apple.systempreferences:",
            "javascript:alert(1)",
            "data:text/html,hi",
            "tel:123",
            "itms-apps://x",
        ] {
            #expect(action(link) == .ignore, "\(link)")
        }
    }

    @Test func aFragmentOrQueryIsDroppedWhenOpeningADocument() {
        #expect(action("file:///Users/me/notes/other.md#section") ==
            .openInApp(URL(fileURLWithPath: "/Users/me/notes/other.md")))
    }

    @Test func aSameDocumentAnchorDoesNotReopenTheDocument() throws {
        let current = URL(fileURLWithPath: "/Users/me/notes/this.md")
        let anchor = try #require(URL(string: "file:///Users/me/notes/this.md#heading"))
        #expect(PreviewLinkResolver.action(for: anchor, currentDocument: current) == .unresolvedInternal("heading"))
    }
}
