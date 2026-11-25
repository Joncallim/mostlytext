import FileCore
import SwiftUI

/// The status bar's line-ending indicator (EPIC-22 §6.17, Slice 8c). Shows
/// what the document actually contains (including Mixed) and offers explicit
/// conversion; nothing is converted implicitly.
struct LineEndingStatusItemView: View {
    @Environment(\.locale) private var locale
    let profile: LineEndingProfile
    let onConvert: (LineEnding) -> Void

    var label: String {
        label(locale: .current)
    }

    func label(locale: Locale, bundle: Bundle = .main) -> String {
        let bundle = ViewLocalizationBundle.resolve(locale: locale, in: bundle)
        return switch profile.kind {
        case .none: String(localized: "No Line Endings", bundle: bundle, locale: locale)
        case .lineFeed: "LF"
        case .crlf: "CRLF"
        case .carriageReturn: "CR"
        case .mixed: String(localized: "Mixed Line Endings", bundle: bundle, locale: locale)
        }
    }

    var body: some View {
        Menu(label(locale: locale)) {
            ForEach(LineEndingChoice.allCases) { choice in
                Toggle(
                    choice.menuTitle(locale: locale),
                    isOn: Binding(
                        get: { profile.uniformEnding == choice.ending },
                        set: { _ in onConvert(choice.ending) }
                    )
                )
                .disabled(profile.kind == .none)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("statusBarLineEnding")
        .help("Line Endings")
    }
}
