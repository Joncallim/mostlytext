import Foundation
import Themes

/// Colors used to render the Markdown preview, derived from the active editor
/// theme and system appearance.
public struct PreviewTheme: Sendable, Equatable {
    public var background: ThemeColor
    public var foreground: ThemeColor
    public var codeBackground: ThemeColor
    public var codeForeground: ThemeColor
    public var linkColor: ThemeColor
    public var quoteColor: ThemeColor
    public var separatorColor: ThemeColor

    public init(
        background: ThemeColor,
        foreground: ThemeColor,
        codeBackground: ThemeColor,
        codeForeground: ThemeColor,
        linkColor: ThemeColor,
        quoteColor: ThemeColor,
        separatorColor: ThemeColor
    ) {
        self.background = background
        self.foreground = foreground
        self.codeBackground = codeBackground
        self.codeForeground = codeForeground
        self.linkColor = linkColor
        self.quoteColor = quoteColor
        self.separatorColor = separatorColor
    }
}

public extension PreviewTheme {
    /// Derives a preview theme from an editor theme.
    ///
    /// The preview uses the editor chrome colours so the two panes feel
    /// cohesive, with small adjustments for block-level elements.
    init(theme: Theme) {
        let palette = ResolvedPresentationPalette(theme: theme)
        background = palette.background
        foreground = palette.foreground
        codeBackground = palette.codeBackground
        codeForeground = palette.codeForeground
        linkColor = palette.link
        quoteColor = palette.quoteForeground
        separatorColor = palette.rule
    }

    static func `default`(for appearance: ThemeAppearance) -> PreviewTheme {
        PreviewTheme(theme: appearance == .dark ? BundledThemes.dark : BundledThemes.light)
    }
}
