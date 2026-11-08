#if EXPORT_BUDGET_RAMP_PROBE
    import CryptoKit
    import Darwin
    import ExportService
    import Foundation
    @testable import MacDown2
    import Testing
    import Themes

    /// One case per fresh hosted Release test process. Fixture preparation and
    /// later evidence inspection run outside this measured app process.
    @Suite(.serialized)
    @MainActor
    struct ExportBudgetRampTests {
        private static let cases: Set<String> = [
            "source8", "source24", "source32", "single8", "single24", "single32",
            "occ16384", "occ65536", "occ65537refusal", "repeat3", "repeat5",
            "repeat6refusal", "aggregate96", "aggregate128", "aggregateOverRefusal",
            "distinct128", "distinct512", "distinct513refusal",
        ]
        private static let marker = Data("data:image/png;base64,".utf8)

        private struct Fixture {
            let name: String
            let root: URL
            let folder: URL
            let source: String
            let sourceBytes: Int
            let resourceBytes: Int
            let occurrences: Int
            let refusal: Bool
            let refusalKind: String?
            let output: URL
            let measurements: URL
        }

        private func fixture() throws -> Fixture {
            let env = ProcessInfo.processInfo.environment
            guard env["GITHUB_ACTIONS"] == "true", env["RUNNER_OS"] == "macOS",
                  env["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
                  NSUserName() == "runner", NSHomeDirectory() == "/Users/runner",
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
                  let name = env["MOSTLYTEXT_EXPORT_BUDGET_RAMP_CASE"], Self.cases.contains(name),
                  let rootPath = env["MOSTLYTEXT_EXPORT_BUDGET_RAMP_ROOT"],
                  rootPath == "/Users/runner/work/_temp/export-budget-ramp",
                  let outputPath = env["MOSTLYTEXT_EXPORT_BUDGET_RAMP_OUTPUT"],
                  outputPath == rootPath + "/cases/" + name + "/measurements" else {
                throw RampError.unownedHost
            }
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let folder = root.appendingPathComponent("fixtures/cases/" + name, isDirectory: true)
            let manifest = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
            guard let row = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
                  let sourceBytes = row["source_bytes"] as? Int,
                  let resourceBytes = row["resource_bytes"] as? Int,
                  let occurrences = row["occurrences"] as? Int,
                  let refusal = row["refusal"] as? Bool,
                  !refusal || row["refusal_kind"] is String,
                  sourceBytes > 0, sourceBytes <= (32 << 20),
                  resourceBytes >= 0, resourceBytes <= (128 << 20) + 1024,
                  occurrences >= 0, occurrences <= 65_537 else {
                throw RampError.fixtureChanged
            }
            let sourceData = try Data(contentsOf: folder.appendingPathComponent("source.md"))
            guard sourceData.count == sourceBytes,
                  let source = String(data: sourceData, encoding: .utf8),
                  row["source_sha256"] as? String == sha256(sourceData) else {
                throw RampError.fixtureChanged
            }
            let measurements = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: measurements, withIntermediateDirectories: true)
            let output = root.appendingPathComponent("cases/" + name + "/export.html")
            guard !FileManager.default.fileExists(atPath: output.path) else { throw RampError.fixtureChanged }
            return Fixture(name: name, root: root, folder: folder, source: source,
                           sourceBytes: sourceBytes, resourceBytes: resourceBytes,
                           occurrences: occurrences, refusal: refusal,
                           refusalKind: row["refusal_kind"] as? String, output: output,
                           measurements: measurements)
        }

        private func sha256(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        private func peakResidentBytes() throws -> Int {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw RampError.residentSampleFailed }
            return Int(usage.ru_maxrss)
        }

        private func outputFacts(_ url: URL) throws -> (bytes: Int, sha256: String, occurrences: Int) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var bytes = 0
            var occurrences = 0
            var tail = Data()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                bytes += chunk.count
                hasher.update(data: chunk)
                let searchable = tail + chunk
                var cursor = searchable.startIndex
                while let range = searchable.range(of: Self.marker, in: cursor ..< searchable.endIndex) {
                    occurrences += 1
                    cursor = range.upperBound
                }
                tail = Data(searchable.suffix(Self.marker.count - 1))
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return (bytes, digest, occurrences)
        }

        private func record(_ fixture: Fixture, values: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fixture.measurements.appendingPathComponent("result.json"), options: .atomic)
        }

        @Test func selectedCase() async throws {
            let input = try fixture()
            let sourceURL = input.folder.appendingPathComponent("source.md")
            let request = try ExportRequest(
                text: input.source, sourceGeneration: 1, theme: BundledThemes.light,
                documentURL: sourceURL,
                resourceAccess: ExportResourceAccess(openingDirectory: input.folder)
            )
            let peakBefore = try peakResidentBytes()
            let start = ProcessInfo.processInfo.systemUptime
            if input.refusal {
                do {
                    _ = try await ExportService.exportHTML(request, to: .html(url: input.output, mode: .selfContained))
                    Issue.record("An over-budget ramp case was published")
                } catch ExportError.budgetExceeded where input.refusalKind == "budget-exceeded" {
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    #expect(!FileManager.default.fileExists(atPath: input.output.path))
                    try record(input, values: [
                        "case": input.name, "outcome": "budget-refusal", "refusal_kind": "budget-exceeded",
                        "source_bytes": input.sourceBytes,
                        "resource_bytes": input.resourceBytes, "occurrences": input.occurrences,
                        "elapsed_seconds": elapsed, "app_peak_before_bytes": peakBefore,
                        "app_peak_after_bytes": try peakResidentBytes(), "output_exists": false,
                    ])
                } catch ExportError.unresolvedResources(let diagnostics)
                    where input.refusalKind == "unresolved-resources" {
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    let limitText = input.name.hasPrefix("aggregate") ? "total resource limit" : "512-resource limit"
                    #expect(diagnostics.contains { $0.message.contains(limitText) })
                    #expect(!FileManager.default.fileExists(atPath: input.output.path))
                    try record(input, values: [
                        "case": input.name, "outcome": "budget-refusal",
                        "refusal_kind": "unresolved-resources", "source_bytes": input.sourceBytes,
                        "resource_bytes": input.resourceBytes, "occurrences": input.occurrences,
                        "elapsed_seconds": elapsed, "app_peak_before_bytes": peakBefore,
                        "app_peak_after_bytes": try peakResidentBytes(), "output_exists": false,
                    ])
                }
            } else {
                _ = try await ExportService.exportHTML(request, to: .html(url: input.output, mode: .selfContained))
                let exportSeconds = ProcessInfo.processInfo.systemUptime - start
                let output = try outputFacts(input.output)
                let readbackSeconds = ProcessInfo.processInfo.systemUptime - start - exportSeconds
                #expect(output.bytes > 0 && output.bytes <= (256 << 20))
                #expect(output.occurrences == input.occurrences)
                try record(input, values: [
                    "case": input.name, "outcome": "published", "source_bytes": input.sourceBytes,
                    "resource_bytes": input.resourceBytes, "occurrences": input.occurrences,
                    "output_bytes": output.bytes, "output_sha256": output.sha256,
                    "export_seconds": exportSeconds, "readback_seconds": readbackSeconds,
                    "app_peak_before_bytes": peakBefore, "app_peak_after_bytes": try peakResidentBytes(),
                ])
            }
        }
    }

    private enum RampError: Error {
        case unownedHost
        case fixtureChanged
        case residentSampleFailed
    }
#endif
