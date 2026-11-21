@testable import D2Rendering
import DiagramsD2
import Testing

@Suite("D2 failure classification")
struct D2FailureClassificationTests {
    @Test func onlyAnActualCompileDiagnosticBlamesAuthoredSyntax() {
        #expect(D2WebRenderer.failure(for: nil, phase: "compile") == .rendererUnavailable)
        #expect(D2WebRenderer.failure(for: " \n", phase: "compile") == .rendererUnavailable)
        #expect(D2WebRenderer.failure(for: "unexpected token", phase: "compile") ==
            .invalidSyntax("unexpected token"))
        #expect(D2WebRenderer.failure(for: "failed to dagre layout: stack overflow", phase: "compile") ==
            .rendererUnavailable)
        #expect(D2WebRenderer.failure(for: "runtime failed", phase: "render") == .rendererUnavailable)
    }
}
