import Foundation
import Testing
import Textual

@MainActor
@Suite("Math transport rejects missing or unauthorised markers")
struct SourceMathAdapterProbeFailureTests {
    @Test func missingDuplicatedAndMisplacedMarkersFallBackToOriginalSource() throws {
        let sample = MathAdapterProbeSample("faults", "Before $x$ after.")
        let spans = try sample.spans()
        let mutations: [(AttributedString) -> AttributedString] = [
            { _ in AttributedString("missing") },
            { value in var output = value; output.append(value); return output },
            { value in AttributedString(String(value.characters)) },
        ]
        for mutation in mutations {
            let result = MathAdapterProbe.parse(sample.source, spans: spans, tamper: mutation)
            #expect(result.fellBack)
            #expect(String(result.text.characters) == sample.source)
            #expect(result.text.runs.allSatisfy { $0.textual.attachment == nil })
        }
    }

    @Test(arguments: ["MT**EQProbeZ**0Q", "&#77;TEQProbeZ0Q"])
    func authoredMarkdownCannotRegisterAnAttachment(_ forged: String) throws {
        let sample = MathAdapterProbeSample("forged", forged + " and $x$")
        let result = try MathAdapterProbe.parse(sample.source, spans: sample.spans(), namespace: "Probe")
        #expect(result.fellBack)
        #expect(String(result.text.characters) == sample.source)
        #expect(result.text.runs.allSatisfy { $0.textual.attachment == nil })
    }

    @Test func preformattedAndOverlappingAdmissionFailsClosed() throws {
        let sample = MathAdapterProbeSample("code", "`$x$`")
        let span = try #require(sample.spans().first)
        let code = MathAdapterProbe.parse(sample.source, spans: [span])
        #expect(code.fellBack)
        let overlap = MathAdapterProbe.Span(range: span.range, latex: span.latex, style: .inline, identifier: UUID())
        let repeated = MathAdapterProbe.parse(sample.source, spans: [span, overlap])
        #expect(repeated.fellBack)
        #expect(String(repeated.text.characters) == sample.source)
    }

    @Test func splitSurrogatesAndNamespaceCollisionsPreserveReadableSource() throws {
        let source = "😀 $x$ MTEQProbeZ"
        let invalid = MathAdapterProbe.Span(
            range: NSRange(location: 1, length: 1),
            latex: "x",
            style: .inline,
            identifier: UUID()
        )
        let result = MathAdapterProbe.parse(source, spans: [invalid])
        #expect(result.fellBack)
        #expect(String(result.text.characters) == source)
        let sample = MathAdapterProbeSample("collision", source)
        let collision = try MathAdapterProbe.parse(source, spans: sample.spans(), namespace: "Probe")
        #expect(collision.fellBack)
        #expect(String(collision.text.characters) == source)
    }
}
