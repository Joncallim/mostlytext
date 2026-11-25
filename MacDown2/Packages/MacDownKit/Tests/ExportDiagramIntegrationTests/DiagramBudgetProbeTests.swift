#if DIAGRAM_BUDGET_PROBE
    import CryptoKit
    import D2Rendering
    import Darwin
    import DiagramRendering
    import Diagrams
    import DiagramsD2
    import DiagramsGraphviz
    import Foundation
    import GraphvizRendering
    import Testing

    @Suite("Hosted diagram budget probe")
    struct DiagramBudgetProbeTests {
        private enum ProbeError: Error { case unownedHost }

        private func verifyHost() throws -> URL {
            let environment = ProcessInfo.processInfo.environment
            guard environment["GITHUB_ACTIONS"] == "true",
                  environment["RUNNER_OS"] == "macOS",
                  environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
                  let temporary = environment["RUNNER_TEMP"],
                  NSHomeDirectory() == "/Users/runner",
                  !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
                  !FileManager.default.fileExists(atPath: "/Users/mostlytexttest") else {
                throw ProbeError.unownedHost
            }
            let directory = URL(fileURLWithPath: temporary).appendingPathComponent("diagram-budget-probe")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        private func peakRSS() -> Int {
            var usage = rusage()
            precondition(getrusage(RUSAGE_SELF, &usage) == 0)
            return Int(usage.ru_maxrss)
        }

        private func digest(_ source: String) -> String {
            SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        private func measure(
            source: String,
            render: (String) async throws -> String
        ) async -> [String: Any] {
            let before = peakRSS()
            let started = ProcessInfo.processInfo.systemUptime
            var record: [String: Any] = [
                "source_bytes": source.utf8.count,
                "source_utf16_units": source.utf16.count,
                "source_sha256": digest(source),
                "test_host_peak_before_rss_bytes": before,
            ]
            do {
                let svg = try await render(source)
                record["outcome"] = "rendered"
                record["svg_bytes"] = svg.utf8.count
                record["svg_sha256"] = digest(svg)
                if let start = svg.range(of: "viewBox=\"") {
                    let remainder = svg[start.upperBound...]
                    if let end = remainder.firstIndex(of: "\"") {
                        let values = remainder[..<end].split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
                        if values.count == 4, values.allSatisfy(\.isFinite) {
                            record["svg_viewbox_width"] = values[2]
                            record["svg_viewbox_height"] = values[3]
                        }
                    }
                }
            } catch {
                record["outcome"] = "refused"
                record["error"] = String(describing: error)
            }
            record["elapsed_seconds"] = ProcessInfo.processInfo.systemUptime - started
            record["test_host_peak_after_rss_bytes"] = peakRSS()
            return record
        }

        private func write(
            _ name: String,
            ordinary: [String: Any],
            stress: [String: Any],
            dense: [String: Any],
            additional: [String: [String: Any]] = [:],
            to directory: URL
        ) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "engine": name, "configuration": "Release", "ordinary": ordinary, "stress": stress,
                "dense": dense, "additional": additional,
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        }

        private func writeCase(_ name: String, result: [String: Any], to directory: URL) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "engine": "d2", "case": name, "configuration": "Release", "result": result,
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        }

        @Test func measureMermaid() async throws {
            let directory = try verifyHost()
            let renderer = MermaidWebRenderer()
            func source(_ edges: Int) -> String {
                "graph TD\n" + (0 ..< edges).map {
                    let child = $0 % 15 + 1
                    return "n\((child - 1) / 2) --> n\(child)"
                }.joined(separator: "\n")
            }
            let ordinary = await measure(source: "graph TD; A-->B;") { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let stress = await measure(source: source(15)) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let dense = await measure(source: source(128)) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let wideSource = "graph LR\n" + (0 ..< 64).map {
                "n\($0) --> n\($0 + 1)"
            }.joined(separator: "\n")
            let tallSource = "graph TD\n" + (0 ..< 64).map {
                "n\($0) --> n\($0 + 1)"
            }.joined(separator: "\n")
            let wide = await measure(source: wideSource) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let tall = await measure(source: tallSource) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let oversized = await measure(source: String(repeating: "a", count: 64 * 1024 + 1)) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            await renderer.shutdown()
            let vectorRenderer = MermaidWebRenderer(poolSize: 1, includeRaster: false)
            let vectorWide = await measure(source: wideSource) { text in
                try await (vectorRenderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                 context: .neutralLight)).svg
            }
            let vectorTall = await measure(source: tallSource) { text in
                try await (vectorRenderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                 context: .neutralLight)).svg
            }
            await vectorRenderer.shutdown()
            var additional = ["wide": wide, "tall": tall, "vectorOnlyWide": vectorWide,
                              "vectorOnlyTall": vectorTall, "sourceOverLimit": oversized]
            let limits = await mermaidLimits()
            additional.merge(limits) { _, latest in latest }
            try write("mermaid", ordinary: ordinary, stress: stress, dense: dense,
                      additional: additional, to: directory)
            #expect(ordinary["outcome"] as? String == "rendered")
            #expect(wide["outcome"] as? String == "rendered")
            #expect(tall["outcome"] as? String == "rendered")
            #expect(vectorWide["outcome"] as? String == "rendered")
            #expect(vectorTall["outcome"] as? String == "rendered")
            #expect((oversized["error"] as? String)?.contains("sourceTooLarge") == true)
        }

        @Test func measureD2() async throws {
            let directory = try verifyHost()
            let renderer = D2WebRenderer()
            func source(_ edges: Int) -> String {
                (0 ..< edges).map { "n\($0) -> n\($0 + 1)" }.joined(separator: "\n")
            }
            let ordinary = await measure(source: source(16)) { text in
                try await (renderer.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let stress = await measure(source: source(128)) { text in
                try await (renderer.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let dense = await measure(source: source(512)) { text in
                try await (renderer.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let oversized = await measure(source: String(repeating: "a", count: 64 * 1024 + 1)) { text in
                try await (renderer.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            await renderer.shutdown()
            let outputBounded = D2WebRenderer(poolSize: 1, maxOutputBytes: 128)
            let outputLimit = await measure(source: source(16)) { text in
                try await (outputBounded.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                context: .neutralLight)).svg
            }
            await outputBounded.shutdown()
            let deadlineBounded = D2WebRenderer(poolSize: 1, timeout: .milliseconds(1))
            let deadline = await measure(source: source(16)) { text in
                try await (deadlineBounded.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                  context: .neutralLight)).svg
            }
            await deadlineBounded.shutdown()
            let limits = ["sourceOverLimit": oversized, "outputOverLimit": outputLimit, "deadline": deadline]
            let mixed = await mixedRendererDocument()
            var additional = limits
            additional["mixedRendererDocument"] = mixed
            try write("d2", ordinary: ordinary, stress: stress, dense: dense,
                      additional: additional, to: directory)
            #expect(ordinary["outcome"] as? String == "rendered")
            #expect((oversized["error"] as? String)?.contains("sourceTooLarge") == true)
            #expect((outputLimit["error"] as? String)?.contains("outputTooLarge") == true)
            #expect((deadline["error"] as? String)?.contains("timedOut") == true)
        }

        @Test func measureD2Chain256() async throws {
            let directory = try verifyHost()
            let renderer = D2WebRenderer()
            let source = (0 ..< 256).map { "n\($0) -> n\($0 + 1)" }.joined(separator: "\n")
            let result = await measure(source: source) { text in
                try await (renderer.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            await renderer.shutdown()
            try writeCase("D2Chain256", result: result, to: directory)
        }

        @Test func measureD2Star256() async throws {
            let directory = try verifyHost()
            let renderer = D2WebRenderer()
            let source = (0 ..< 256).map { "root -> n\($0)" }.joined(separator: "\n")
            let result = await measure(source: source) { text in
                try await (renderer.render(D2Fence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            await renderer.shutdown()
            try writeCase("D2Star256", result: result, to: directory)
        }

        @Test func measureGraphviz() async throws {
            let directory = try verifyHost()
            let renderer = GraphvizWebRenderer()
            func source(_ edges: Int) -> String {
                "digraph {\n" + (0 ..< edges).map {
                    "n\($0) -> n\($0 + 1) [label=\"edge \($0)\"];"
                }.joined(separator: "\n") + "\n}"
            }
            let ordinary = await measure(source: source(16)) { text in
                try await (renderer.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let stress = await measure(source: source(128)) { text in
                try await (renderer.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let dense = await measure(source: source(512)) { text in
                try await (renderer.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let wide = await measure(source: "digraph { rankdir=LR; " + (0 ..< 128).map {
                "n\($0) -> n\($0 + 1);"
            }.joined(separator: " ") + " }") { text in
                try await (renderer.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let tall = await measure(source: "digraph { " + (0 ..< 128).map {
                "n\($0) -> n\($0 + 1);"
            }.joined(separator: " ") + " }") { text in
                try await (renderer.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let oversized = await measure(source: String(repeating: "a", count: 64 * 1024 + 1)) { text in
                try await (renderer.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            await renderer.shutdown()
            var additional = ["wide": wide, "tall": tall, "sourceOverLimit": oversized]
            let limits = await graphvizLimits()
            additional.merge(limits) { _, latest in latest }
            try write("graphviz", ordinary: ordinary, stress: stress, dense: dense,
                      additional: additional, to: directory)
            #expect(ordinary["outcome"] as? String == "rendered")
            #expect((oversized["error"] as? String)?.contains("sourceTooLarge") == true)
        }
    }

    private extension DiagramBudgetProbeTests {
        func mermaidLimits() async -> [String: [String: Any]] {
            let outputBounded = MermaidWebRenderer(poolSize: 1, maxOutputBytes: 128)
            let outputLimit = await measure(source: "graph TD; A-->B;") { text in
                try await (outputBounded.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                context: .neutralLight)).svg
            }
            await outputBounded.shutdown()
            let deadlineBounded = MermaidWebRenderer(poolSize: 1, timeout: .milliseconds(1))
            let deadline = await measure(source: "graph TD; A-->B;") { text in
                try await (deadlineBounded.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                  context: .neutralLight)).svg
            }
            await deadlineBounded.shutdown()
            #expect((outputLimit["error"] as? String)?.contains("outputTooLarge") == true)
            #expect((deadline["error"] as? String)?.contains("timedOut") == true)
            return ["outputOverLimit": outputLimit, "deadline": deadline]
        }

        func graphvizLimits() async -> [String: [String: Any]] {
            let source = "digraph { a -> b; }"
            let outputBounded = GraphvizWebRenderer(poolSize: 1, maxOutputBytes: 128)
            let outputLimit = await measure(source: source) { text in
                try await (outputBounded.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                context: .neutralLight)).svg
            }
            await outputBounded.shutdown()
            let deadlineBounded = GraphvizWebRenderer(poolSize: 1, timeout: .milliseconds(1))
            let deadline = await measure(source: source) { text in
                try await (deadlineBounded.render(GraphvizFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                                  context: .neutralLight)).svg
            }
            await deadlineBounded.shutdown()
            #expect((outputLimit["error"] as? String)?.contains("outputTooLarge") == true)
            #expect((deadline["error"] as? String)?.contains("timedOut") == true)
            return ["outputOverLimit": outputLimit, "deadline": deadline]
        }

        func mixedRendererDocument() async -> [String: Any] {
            let started = ProcessInfo.processInfo.systemUptime
            let mermaid = MermaidWebRenderer(poolSize: 1)
            let d2Renderer = D2WebRenderer(poolSize: 1)
            let graphviz = GraphvizWebRenderer(poolSize: 1)
            let mermaidSource = "graph TD; A-->B;"
            let d2Source = "a -> b"
            let graphvizSource = "digraph { a -> b; }"
            let mermaidResult = await measure(source: mermaidSource) { source in
                try await (mermaid.render(MermaidFence(source: source, sourceRange: 0 ..< source.utf16.count),
                                          context: .neutralLight)).svg
            }
            let d2Result = await measure(source: d2Source) { source in
                try await (d2Renderer.render(D2Fence(source: source, sourceRange: 0 ..< source.utf16.count),
                                             context: .neutralLight)).svg
            }
            let graphvizResult = await measure(source: graphvizSource) { source in
                try await (graphviz.render(GraphvizFence(source: source, sourceRange: 0 ..< source.utf16.count),
                                           context: .neutralLight)).svg
            }
            await mermaid.shutdown()
            await d2Renderer.shutdown()
            await graphviz.shutdown()
            var record: [String: Any] = ["mermaid": mermaidResult, "d2": d2Result, "graphviz": graphvizResult]
            record["elapsed_seconds"] = ProcessInfo.processInfo.systemUptime - started
            return record
        }
    }
#endif
