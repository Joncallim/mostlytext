import Foundation
import Math
import SwiftUIMath

/// Shared admission and actual parser outcomes, before either presentation adapter.
/// No font loading, glyph geometry or UI execution is needed to prepare this value.
public struct MathEvaluation: Sendable {
    public struct Entry: Sendable, Identifiable {
        public enum Outcome: Sendable {
            case accepted(SwiftUIMath.Math.ValidatedBody)
            case rejected(MathEquationDiagnostic)
        }

        public var id: UUID {
            equation.id
        }

        public let equation: MathEquation
        public let outcome: Outcome
    }

    public let analysis: MathAnalysis
    public let entries: [Entry]

    public static func evaluate(
        analysis: MathAnalysis, limits: SwiftUIMath.Math.BodyLimits
    ) throws -> Self {
        var entries: [Entry] = []
        entries.reserveCapacity(analysis.equations.count)
        for equation in analysis.equations {
            try Task.checkCancellation()
            let outcome: Entry.Outcome = switch try SwiftUIMath.Math.validateBody(
                equation.rendererExpression,
                limits: limits
            ) {
            case let .valid(body): .accepted(body)
            case let .invalid(problem):
                .rejected(diagnostic(equation, kind: category(problem.error.code), offset: problem.utf16Offset))
            case let .internalFailure(problem):
                .rejected(diagnostic(equation, kind: .internalFailure, offset: problem.utf16Offset))
            case .resourceLimit:
                .rejected(diagnostic(equation, kind: .resourceLimit, offset: 0))
            }
            entries.append(Entry(equation: equation, outcome: outcome))
        }
        try Task.checkCancellation()
        return Self(analysis: analysis, entries: entries)
    }

    private static func diagnostic(
        _ equation: MathEquation, kind: MathEquationDiagnostic.Kind, offset: Int
    ) -> MathEquationDiagnostic {
        MathEquationDiagnostic(
            equationID: equation.id, kind: kind,
            sourceOffset: equation.sourceOffset(forRenderedUTF16Offset: offset) ?? equation.syntax.bodyRange.lowerBound
        )
    }

    private static func category(_ code: SwiftUIMath.Math.ParserError.Code) -> MathEquationDiagnostic.Kind {
        switch code {
        case .invalidCommand: .unrecognizedCommand
        case .characterNotFound: .unsupportedCharacter
        case .invalidEnvironment, .missingEnvironment, .missingBegin, .missingEnd, .invalidNumberOfColumns:
            .invalidEnvironment
        case .internalError: .internalFailure
        case .mismatchedBraces, .missingDelimiter, .invalidDelimiter, .missingRight, .missingLeft, .invalidLimits:
            .invalidSyntax
        }
    }
}
