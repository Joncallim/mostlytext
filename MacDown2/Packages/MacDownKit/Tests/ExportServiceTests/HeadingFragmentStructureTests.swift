@testable import ExportService
import Foundation
import Testing

struct HeadingFragmentStructureTests {
    @Test(arguments: [
        "", "Readable 東京 &lt;h1 id=x&gt; &amp; text",
        "<ul>\n<li><a href=\"#caf%C3%A9\">Café</a><ul><li>Child</li></ul></li>\n</ul>\n",
        "<p><em>(No headings found.)</em></p>\n",
        "<ol start=\"9\"><li><p>One</p><p>Two</p></li></ol>",
        "<img src=\"data:image/png;base64,AAAA\" width=\"9\" height=\"8\" alt=\"&quot;&lt; &amp;\">",
        "<p><strong>A <em>B</em></strong><br />C <del>D</del> <code>&lt;svg&gt;</code></p>",
    ])
    func balancedIdentifierFreeFragmentsAreAdmitted(_ html: String) {
        #expect(HeadingFragmentStructure.accepts(html, isBlock: true))
    }

    @Test(arguments: [
        "<h1>Invented</h1>", "<a id=\"target\">A</a>", "<a name=\"target\">A</a>",
        "<p ID=\"target\">A</p>", "<p data-id=\"target\">A</p>", "<svg></svg>",
        "<math><mtext>A</mtext></math>", "<!-- hidden -->", "<!doctype html>",
        "<script></script>", "<style></style>", "<textarea></textarea>", "<plaintext>",
        "<template></template>", "<table><tr><td>A</td></tr></table>",
        "</p><p>A</p>", "<p>A", "<p><ul><li>A</li></ul></p>", "<li>A</li>",
        "<ul>not a list item<li>A</li></ul>", "<ul>&#65;<li>A</li></ul>",
        "<ul><p>A</p></ul>", "<a href=\"#a\"><em><a href=\"#b\">B</a></em></a>",
        "<p/>", "<br></br>", "<IMG>", "<p\u{0C}>A</p>", "A\0B",
        "<a href=#x>A</a>", "<a href=\"#x\"href=\"#y\">A</a>",
        "<a href=\"#x\" href=\"#y\">A</a>", "<a href=\"<p>\">A</a>",
        "<img src=\"x\" onerror=\"bad\">", "<img src=\"x\" style=\"x\">",
        "<a href=\"#x\n\">A</a>", "<a href=\"unterminated>A</a>",
        "<p>A</p trailing>", "<p>A</p/><p>B</p>", "<br / >", "<?processing?>",
    ])
    func unknownOrRepairingMarkupNeedsDOMAnalysis(_ html: String) {
        #expect(!HeadingFragmentStructure.accepts(html, isBlock: true))
    }

    @Test func inlineFragmentsCannotCloseOrIntroduceBlockContexts() {
        #expect(HeadingFragmentStructure.accepts("<em>A</em><br><img src='x'>", isBlock: false))
        #expect(!HeadingFragmentStructure.accepts("<a href='#a'>A</a>", isBlock: false))
        #expect(!HeadingFragmentStructure.accepts("<p>A</p>", isBlock: false))
        #expect(!HeadingFragmentStructure.accepts("<ul><li>A</li></ul>", isBlock: false))
    }

    @Test func depthIsBoundedAndCheckedBeforePushing() {
        let depth = HeadingFragmentStructure.maximumDepth
        let accepted = String(repeating: "<em>", count: depth) + "A" + String(repeating: "</em>", count: depth)
        #expect(HeadingFragmentStructure.accepts(accepted, isBlock: false))
        #expect(!HeadingFragmentStructure.accepts("<em>" + accepted + "</em>", isBlock: false))
    }

    @Test func largeImageValuesDoNotAcquireTheDOMByteCap() {
        let html = "<img src='data:image/png;base64," + String(repeating: "A", count: 9 * 1024 * 1024) + "' alt='x'>"
        #expect(HeadingFragmentStructure.accepts(html, isBlock: false))
    }
}
