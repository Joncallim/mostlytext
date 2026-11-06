import AppKit
import EditorCore
import Highlighting
import Testing
import Themes

@MainActor
struct CurrentLineThemeForwardingTests {
    @Test func liveChromeUsesTheSingleResolvedPaletteWithoutEditingSource() throws {
        let system = EditorTextSystem(identity: "palette-roles", initialText: "plain text", configuration: .default)
        let editor = try #require(system.textView as? EditorTextView)
        let highlighter = NeonSyntaxHighlighter(textSystem: system, languageID: nil,
                                                theme: BundledThemes.light, registry: GrammarRegistry())
        defer { highlighter.tearDown() }
        let selection = system.selectionSet
        for theme in BundledThemes.all {
            highlighter.applyTheme(theme)
            let palette = ResolvedPresentationPalette(theme: theme)
            #expect(editor.currentLineColor == palette.currentLine.nsColor)
            #expect(editor.gutterForegroundColor == palette.gutterForeground.nsColor)
            #expect(editor.gutterBackgroundColor == palette.gutterBackground.nsColor)
            #expect(editor.invisiblesColor == palette.invisibles.nsColor)
            #expect(system.text == "plain text" && system.selectionSet == selection)
        }
    }
}
