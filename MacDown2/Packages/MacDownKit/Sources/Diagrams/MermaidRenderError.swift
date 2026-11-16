import Foundation

/// Failure modes for a Mermaid render (epic-20-implementation.md §9).
public enum MermaidRenderError: Error, Sendable, Equatable {
    /// Mermaid's own parse-error message, where available.
    case invalidSyntax(String)
    case timedOut
    case sourceTooLarge(byteCount: Int)
    case outputTooLarge(byteCount: Int)
    /// The offscreen renderer failed to initialize (e.g. a WebKit process
    /// launch failure). Retried on the next render call, not permanently
    /// fatal for the rest of the app session.
    case rendererUnavailable
}
