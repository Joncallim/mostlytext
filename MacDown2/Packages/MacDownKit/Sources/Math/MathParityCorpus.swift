import Foundation

/// Compatibility corpus for the legacy String/span rendering APIs and the
/// historical Preview preprocessor. Its zero-size validity convention is kept
/// for those callers. Production uses the shared MathAnalysis/MathEvaluation
/// policy; valid no-visible-output bodies have a distinct source fallback.
/// The production app parity controls live in SharedMathActivationTests.
public enum MathParityCorpus {
    public struct Case: Sendable {
        public let latex: String
        public let style: MathSpan.Style
        public let isRenderable: Bool
        public let comment: String

        public init(latex: String, style: MathSpan.Style, isRenderable: Bool, comment: String) {
            self.latex = latex
            self.style = style
            self.isRenderable = isRenderable
            self.comment = comment
        }
    }

    public static let cases: [Case] = [
        .init(latex: "x=1", style: .inline, isRenderable: true, comment: "simple inline equation"),
        .init(latex: "E = mc^2", style: .inline, isRenderable: true, comment: "spaced inline equation"),
        .init(
            latex: "\\frac{1}{2}+\\sqrt{2}", style: .display, isRenderable: true,
            comment: "fraction and square root"
        ),
        .init(
            latex: "\\sum_{i=1}^{n}x_i", style: .display, isRenderable: true,
            comment: "large operator with sub/superscript"
        ),
        .init(latex: "\\alpha+\\beta=\\gamma", style: .inline, isRenderable: true, comment: "Greek letters"),
        .init(
            latex: "A=\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}", style: .display, isRenderable: true,
            comment: "matrix environment"
        ),
        .init(latex: "\\frac{1}{", style: .inline, isRenderable: false, comment: "unbalanced brace"),
        .init(latex: "\\left(", style: .inline, isRenderable: false, comment: "\\left with no matching \\right"),
        .init(latex: "\\begin{cases}", style: .display, isRenderable: false, comment: "\\begin with no \\end"),
        .init(latex: "\\notaknowncommand", style: .inline, isRenderable: false, comment: "unknown command"),
        .init(latex: "", style: .inline, isRenderable: false, comment: "empty inline expression"),
        .init(latex: "", style: .display, isRenderable: false, comment: "empty display expression"),
    ]
}
