import Foundation

/// Failure modes for a Graphviz render, mirroring `MermaidRenderError`.
public enum GraphvizRenderError: Error, Sendable, Equatable {
    case invalidSyntax(String)
    case timedOut
    case sourceTooLarge(byteCount: Int)
    case outputTooLarge(byteCount: Int)
    case rendererUnavailable
}
