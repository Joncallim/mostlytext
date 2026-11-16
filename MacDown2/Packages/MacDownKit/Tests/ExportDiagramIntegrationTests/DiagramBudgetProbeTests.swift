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
                "source_sha256": digest(source),
                "app_peak_before_rss_bytes": before,
            ]
            do {
                let svg = try await render(source)
                record["outcome"] = "rendered"
                record["svg_bytes"] = svg.utf8.count
                record["svg_sha256"] = digest(svg)
            } catch {
                record["outcome"] = "refused"
                record["error"] = String(describing: error)
            }
            record["elapsed_seconds"] = ProcessInfo.processInfo.systemUptime - started
            record["app_peak_after_rss_bytes"] = peakRSS()
            return record
        }

        private func write(
            _ name: String,
            ordinary: [String: Any],
            stress: [String: Any],
            dense: [String: Any],
            to directory: URL
        ) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "engine": name, "configuration": "Release", "ordinary": ordinary, "stress": stress, "dense": dense,
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        }

        @Test func measureMermaid() async throws {
            let directory = try verifyHost()
            let renderer = MermaidWebRenderer()
            func source(_ edges: Int) -> String {
                "graph LR\n" + (0 ..< edges).map {
                    "n\($0)[Node \($0)] --> n\($0 + 1)[Node \($0 + 1)]"
                }.joined(separator: "\n")
            }
            let ordinary = await measure(source: source(16)) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let stress = await measure(source: source(128)) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            let dense = await measure(source: source(512)) { text in
                try await (renderer.render(MermaidFence(source: text, sourceRange: 0 ..< text.utf16.count),
                                           context: .neutralLight)).svg
            }
            await renderer.shutdown()
            try write("mermaid", ordinary: ordinary, stress: stress, dense: dense, to: directory)
            #expect(ordinary["outcome"] as? String == "rendered")
            #expect(stress["outcome"] as? String == "rendered")
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
            await renderer.shutdown()
            try write("d2", ordinary: ordinary, stress: stress, dense: dense, to: directory)
            #expect(ordinary["outcome"] as? String == "rendered")
            #expect(stress["outcome"] as? String == "rendered")
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
            await renderer.shutdown()
            try write("graphviz", ordinary: ordinary, stress: stress, dense: dense, to: directory)
            #expect(ordinary["outcome"] as? String == "rendered")
            #expect(stress["outcome"] as? String == "rendered")
        }
    }
#endif
