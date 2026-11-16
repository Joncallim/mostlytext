import D2Rendering
import DiagramRendering
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import DiagramWebKitPool
import GraphvizRendering
import Testing

@Suite("Diagram source admission")
struct DiagramSourceAdmissionTests {
    @Test func byteBoundaryUsesUTF8WithoutCopyingSource() {
        let limit = DiagramSourceBudget.maximumUTF8Bytes
        #expect(DiagramSourceBudget.byteCountIfOversized(String(repeating: "a", count: limit)) == nil)
        #expect(DiagramSourceBudget.byteCountIfOversized(String(repeating: "a", count: limit + 1)) == limit + 1)
        #expect(DiagramSourceBudget.byteCountIfOversized(String(repeating: "é", count: limit / 2)) == nil)
        #expect(DiagramSourceBudget.byteCountIfOversized(String(repeating: "é", count: limit / 2 + 1)) == limit + 2)
    }

    @Test func allEnginesRefuseOversizedSourceBeforeCreatingAPage() async {
        let source = String(repeating: "x", count: DiagramSourceBudget.maximumUTF8Bytes + 1)
        let range = 0 ..< source.utf16.count
        let mermaid = MermaidWebRenderer()
        do {
            _ = try await mermaid.render(MermaidFence(source: source, sourceRange: range), context: .neutralLight)
            Issue.record("Mermaid accepted an oversized authored source")
        } catch let error as MermaidRenderError {
            #expect(error == .sourceTooLarge(byteCount: source.utf8.count))
        } catch {
            Issue.record("Mermaid returned \(error)")
        }
        await mermaid.shutdown()

        let d2Renderer = D2WebRenderer()
        do {
            _ = try await d2Renderer.render(D2Fence(source: source, sourceRange: range), context: .neutralLight)
            Issue.record("D2 accepted an oversized authored source")
        } catch let error as D2RenderError {
            #expect(error == .sourceTooLarge(byteCount: source.utf8.count))
        } catch {
            Issue.record("D2 returned \(error)")
        }
        await d2Renderer.shutdown()

        let graphviz = GraphvizWebRenderer()
        do {
            _ = try await graphviz.render(GraphvizFence(source: source, sourceRange: range), context: .neutralLight)
            Issue.record("Graphviz accepted an oversized authored source")
        } catch let error as GraphvizRenderError {
            #expect(error == .sourceTooLarge(byteCount: source.utf8.count))
        } catch {
            Issue.record("Graphviz returned \(error)")
        }
        await graphviz.shutdown()
    }

    @Test func cancelledWorkKeepsCancellationPrecedenceOverSourceRefusal() async {
        let source = String(repeating: "x", count: DiagramSourceBudget.maximumUTF8Bytes + 1)
        let range = 0 ..< source.utf16.count
        let mermaid = MermaidWebRenderer()
        let d2Renderer = D2WebRenderer()
        let graphviz = GraphvizWebRenderer()
        let cancelled = await Task { () -> [Bool] in
            withUnsafeCurrentTask { $0?.cancel() }
            var results: [Bool] = []
            do {
                _ = try await mermaid.render(MermaidFence(source: source, sourceRange: range), context: .neutralLight)
                results.append(false)
            } catch is CancellationError {
                results.append(true)
            } catch {
                results.append(false)
            }
            do {
                _ = try await d2Renderer.render(D2Fence(source: source, sourceRange: range), context: .neutralLight)
                results.append(false)
            } catch is CancellationError {
                results.append(true)
            } catch {
                results.append(false)
            }
            do {
                _ = try await graphviz.render(GraphvizFence(source: source, sourceRange: range), context: .neutralLight)
                results.append(false)
            } catch is CancellationError {
                results.append(true)
            } catch {
                results.append(false)
            }
            return results
        }.value
        #expect(cancelled == [true, true, true])
        await mermaid.shutdown()
        await d2Renderer.shutdown()
        await graphviz.shutdown()
    }
}
