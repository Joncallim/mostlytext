import FileCore
import SwiftUI

extension WorkspaceCommands {
    /// The "Convert Line Endings" submenu inside the "Lines" menu. A second
    /// `CommandMenu("Lines")` would create a separate menu, so this is
    /// composed into `lineTransformCommands` instead.
    var convertLineEndingsMenu: some View {
        Menu("Convert Line Endings") {
            ForEach(LineEndingChoice.allCases) { choice in
                Button(choice.menuTitle(locale: locale)) {
                    coordinator?.convertKeyDocumentLineEndings(to: choice.ending)
                }
                .disabled(coordinator?.canConvertLineEndings != true)
            }
        }
    }
}

/// The three conversion targets, shared by the menu bar and the status bar.
enum LineEndingChoice: CaseIterable, Identifiable {
    case lineFeed
    case crlf
    case carriageReturn

    var id: Self {
        self
    }

    var ending: LineEnding {
        switch self {
        case .lineFeed: .lineFeed
        case .crlf: .crlf
        case .carriageReturn: .carriageReturn
        }
    }

    var menuTitle: String {
        menuTitle(locale: .current)
    }

    func menuTitle(locale: Locale, bundle: Bundle = .main) -> String {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        return switch self {
        case .lineFeed: String(localized: "LF (Unix, macOS)", bundle: bundle, locale: locale)
        case .crlf: String(localized: "CRLF (Windows)", bundle: bundle, locale: locale)
        case .carriageReturn: String(localized: "CR (Classic Mac OS)", bundle: bundle, locale: locale)
        }
    }

    var shortName: String {
        switch self {
        case .lineFeed: "LF"
        case .crlf: "CRLF"
        case .carriageReturn: "CR"
        }
    }
}
