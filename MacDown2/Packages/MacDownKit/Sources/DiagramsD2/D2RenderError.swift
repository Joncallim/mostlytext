import Foundation

/// Failure modes for a D2 render, mirroring `MermaidRenderError`'s shape.
public enum D2RenderError: Error, Sendable, Equatable {
    case invalidSyntax(String)
    case timedOut
    case sourceTooLarge(byteCount: Int)
    case outputTooLarge(byteCount: Int)
    case rendererUnavailable
}
