import Foundation

/// A first-party category and a boundary in the author's original source.
/// Engine free-text messages are deliberately not user-facing diagnostics.
public struct MathEquationDiagnostic: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case invalidSyntax
        case unrecognizedCommand
        case unsupportedCharacter
        case invalidEnvironment
        case resourceLimit
        case internalFailure
        case renderingFailed
    }

    public let equationID: UUID
    public let kind: Kind
    public let sourceOffset: Int

    public init(equationID: UUID, kind: Kind, sourceOffset: Int) {
        self.equationID = equationID
        self.kind = kind
        self.sourceOffset = sourceOffset
    }
}
