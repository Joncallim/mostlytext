import Foundation

/// Resolves a catalog lookup for a view's language, including SwiftUI locale
/// overrides. `String(localized:locale:)` formats values in that locale but
/// does not choose a different localization from a multilingual bundle.
public enum ViewLocalizationBundle {
    public static func resolve(locale: Locale, in bundle: Bundle) -> Bundle {
        let preferred = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [locale.identifier]
        )
        guard let language = preferred.first,
              let resourceURL = bundle.url(forResource: language, withExtension: "lproj"),
              let localizedBundle = Bundle(url: resourceURL) else {
            return bundle
        }
        return localizedBundle
    }
}
