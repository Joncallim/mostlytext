import Foundation

/// Rendering failures are isolated to their equation. The legacy String API
/// maps empty output to couldNotTypeset. The typed, parser-valid body API keeps
/// zero-ink output separate from malformed input; resource and invalid-geometry
/// failures do not claim the author's source has invalid syntax.
public enum MathRenderError: Error, Sendable, Equatable {
    case couldNotTypeset
    case invalidImageDimensions
    case resourceLimit
    /// A parser-valid body with no visible geometry; never a malformed-source claim.
    case noVisibleOutput
}
