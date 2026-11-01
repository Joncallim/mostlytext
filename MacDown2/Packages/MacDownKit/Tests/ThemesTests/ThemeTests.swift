import Foundation
import Testing
@testable import Themes

struct ThemeTests {
    private let sampleTheme = Theme(
        id: "test",
        name: "Test",
        appearance: .light,
        chrome: EditorChrome(
            background: ThemeColor(red: 1, green: 1, blue: 1),
            foreground: ThemeColor(red: 0, green: 0, blue: 0),
            caret: ThemeColor(red: 0, green: 0, blue: 0),
            selection: ThemeColor(red: 0.5, green: 0.5, blue: 0.5)
        ),
        tokenStyles: [
            "keyword": TokenStyle(color: ThemeColor(red: 1, green: 0, blue: 0)),
            "string": TokenStyle(color: ThemeColor(red: 0, green: 1, blue: 0)),
        ]
    )

    @Test func exactMatch() {
        let style = sampleTheme.style(for: "keyword")
        #expect(style?.color.red == 1.0)
    }

    @Test func fallbackChain() {
        let style = sampleTheme.style(for: "keyword.control")
        #expect(style?.color.red == 1.0)
    }

    @Test func fallbackStopsAtRoot() {
        let style = sampleTheme.style(for: "unknown.sub.segment")
        #expect(style == nil)
    }

    @Test func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(sampleTheme)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Theme.self, from: data)
        #expect(decoded == sampleTheme)
    }

    @Test func bundledThemesDecode() {
        #expect(BundledThemes.light.id == "tomorrow-light")
        #expect(BundledThemes.dark.id == "tomorrow-dark")
        #expect(BundledThemes.all.count >= 8)
    }

    @Test func bundledThemesCoverCanonicalRoots() {
        let roots: Set = [
            "keyword", "string", "comment", "number", "constant",
            "function", "type", "variable", "property", "operator",
            "punctuation", "tag", "markup.heading", "markup.bold",
            "markup.italic", "markup.link", "markup.raw", "markup.list",
            "markup.quote", "label", "embedded",
        ]
        for theme in BundledThemes.all {
            for root in roots {
                #expect(theme.style(for: root) != nil, "Theme \(theme.id) missing style for \(root)")
            }
        }
    }
}
