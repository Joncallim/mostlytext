#if EXPORT_BUDGET_PROBE
    import ExportService
    import Foundation
    @testable import MacDown2
    import Testing
    import Themes

    extension ExportBudgetCalibrationTests {
        @Test func resourceReadAttemptLimitIncludesMissingFiles() async throws {
            _ = try outputDirectory()
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("read-attempts.html")
            let source = (0 ... 4096).map { "![image](missing-\($0).png)" }.joined(separator: "\n")
            let sourceURL = root.appendingPathComponent("source.md")
            try Data(source.utf8).write(to: sourceURL)
            let request = try ExportRequest(
                text: source, sourceGeneration: 1, theme: BundledThemes.light,
                documentURL: sourceURL, resourceAccess: ExportResourceAccess(openingDirectory: root)
            )
            let peakBefore = try peakResidentBytes()
            let started = ProcessInfo.processInfo.systemUptime
            do {
                _ = try await ExportService.exportHTML(
                    request, to: .html(url: destination, mode: .selfContained)
                )
                Issue.record("The export admitted a 4,097th distinct read attempt")
            } catch let ExportError.unresolvedResources(diagnostics) {
                #expect(diagnostics.contains { $0.message.contains("read-work limit") })
                #expect(!FileManager.default.fileExists(atPath: destination.path))
                try record("read-attempts", values: [
                    "case": "actual-read-attempt-limit-refusal", "source_bytes": source.utf8.count,
                    "source_sha256": sha256(Data(source.utf8)), "references": 4097,
                    "output_exists": false,
                    "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started,
                    "app_peak_before_rss_bytes": peakBefore,
                    "app_peak_rss_bytes": peakResidentBytes(),
                ])
            }
        }

        @Test func resourceReadByteLimitIncludesRejectedNonImages() async throws {
            _ = try outputDirectory()
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("read-bytes.html")
            let first = root.appendingPathComponent("nonimage-0.txt")
            let payload = Data(repeating: 0x41, count: 32 << 20)
            try payload.write(to: first)
            for index in 1 ..< 8 {
                try FileManager.default.linkItem(
                    at: first, to: root.appendingPathComponent("nonimage-\(index).txt")
                )
            }
            let source = (0 ..< 8).map { "![image](nonimage-\($0).txt)" }.joined(separator: "\n") +
                "\n![image](pixel.png)"
            let sourceURL = root.appendingPathComponent("source.md")
            try Data(source.utf8).write(to: sourceURL)
            let request = try ExportRequest(
                text: source, sourceGeneration: 1, theme: BundledThemes.light,
                documentURL: sourceURL, resourceAccess: ExportResourceAccess(openingDirectory: root)
            )
            let peakBefore = try peakResidentBytes()
            let started = ProcessInfo.processInfo.systemUptime
            do {
                _ = try await ExportService.exportHTML(
                    request, to: .html(url: destination, mode: .selfContained)
                )
                Issue.record("The export admitted a read after 256 MiB of rejected bytes")
            } catch let ExportError.unresolvedResources(diagnostics) {
                #expect(diagnostics.contains { $0.message.contains("read-work limit") })
                #expect(!FileManager.default.fileExists(atPath: destination.path))
                try record("read-bytes", values: [
                    "case": "actual-rejected-read-byte-limit-refusal", "source_bytes": source.utf8.count,
                    "source_sha256": sha256(Data(source.utf8)), "linked_file_bytes": payload.count,
                    "charged_read_bytes": 8 * payload.count, "output_exists": false,
                    "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started,
                    "app_peak_before_rss_bytes": peakBefore,
                    "app_peak_rss_bytes": peakResidentBytes(),
                ])
            }
        }
    }
#endif
