import Foundation

/// App-owned context around renderer failures. Engine syntax messages remain
/// literal in their existing callers; this value formats only known states.
enum DiagramFailurePresentation: Sendable {
    case noPreviewImage
    case timedOut
    case outputTooLarge(byteCount: Int)
    case rendererUnavailable

    func message(bundle: Bundle = .main, locale: Locale = .current) -> String {
        switch self {
        case .noPreviewImage:
            String(localized: "no preview image was produced", bundle: bundle, locale: locale)
        case .timedOut:
            String(localized: "rendering timed out", bundle: bundle, locale: locale)
        case let .outputTooLarge(byteCount):
            String(localized: "rendered output too large (\(byteCount) bytes)", bundle: bundle, locale: locale)
        case .rendererUnavailable:
            String(localized: "renderer unavailable", bundle: bundle, locale: locale)
        }
    }
}
