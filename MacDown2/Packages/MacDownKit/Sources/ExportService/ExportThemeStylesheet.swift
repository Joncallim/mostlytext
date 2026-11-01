import Foundation
import Themes

/// Turns the active `Theme` into the CSS variable block used by the bundled
/// structural stylesheet.
///
/// Theme reuse is deliberate: every export theme shares the one structural
/// stylesheet (`Resources/structural.css`) and differs only by the `--md-*`
/// custom properties emitted here. There is no per-theme CSS copy and no
/// separate export palette.
public enum ExportThemeStylesheet {
    /// The `:root { … }` variable block derived from `theme.chrome`.
    public static func variables(for theme: Theme) -> String {
        let palette = ResolvedPresentationPalette(theme: theme)
        return """
        :root {
          color-scheme: \(theme.appearance == .dark ? "dark" : "light");
          --md-background: \(css(palette.background));
          --md-foreground: \(css(palette.foreground));
          --md-heading: \(css(palette.heading));
          --md-link: \(css(palette.link));
          --md-muted: \(css(palette.muted));
          --md-rule: \(css(palette.rule));
          --md-code-bg: \(css(palette.codeBackground));
        }
        """
    }

    /// The single bundled structural stylesheet, read once per process. Every
    /// export uses the same bytes, so re-reading the bundle per export would be
    /// pure filesystem work for an identical result.
    public static let structural: String = {
        guard let url = Bundle.module.url(forResource: "structural", withExtension: "css"),
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Bundled structural stylesheet is missing; falling back to empty CSS.")
            return ""
        }
        return data
    }()

    private static func css(_ color: ThemeColor) -> String {
        let red = channel(color.red)
        let green = channel(color.green)
        let blue = channel(color.blue)
        if color.alpha >= 0.999 {
            return String(format: "#%02x%02x%02x", red, green, blue)
        }
        return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, min(max(color.alpha, 0), 1))
    }

    /// A theme colour is nominally 0…1, but a malformed theme must still produce
    /// parseable CSS rather than something like `#-1ff00`.
    private static func channel(_ value: Double) -> Int {
        min(max(Int((value * 255).rounded()), 0), 255)
    }
}
