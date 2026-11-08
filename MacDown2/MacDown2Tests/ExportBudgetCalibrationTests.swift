#if EXPORT_BUDGET_PROBE
    import CryptoKit
    import Darwin
    import ExportService
    import Foundation
    @testable import MacDown2
    import PDFKit
    import Testing
    import Themes

    /// Opt-in Release measurements of the production export path. These samples
    /// describe this fixture and machine; they do not set or prove a safe cap.
    @Suite(.serialized)
    @MainActor
    struct ExportBudgetCalibrationTests {
        private static let sourceLimit = 32 << 20
        private static let pixelBase64 = """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5W0ZkAAAAASUVORK5CYII=
        """

        private func outputDirectory() throws -> URL {
            let environment = ProcessInfo.processInfo.environment
            guard environment["GITHUB_ACTIONS"] == "true",
                  environment["RUNNER_OS"] == "macOS",
                  environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
                  NSUserName() == "runner",
                  NSHomeDirectory() == "/Users/runner",
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
                  let path = environment["MOSTLYTEXT_EXPORT_BUDGET_OUTPUT"],
                  path == "/Users/runner/work/_temp/export-budget-calibration/measurements" else {
                throw CalibrationError.unownedHost
            }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func record(_ name: String, values: [String: Any]) throws {
            let directory = try outputDirectory()
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        }

        private func peakResidentBytes() throws -> Int {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw CalibrationError.residentSampleFailed }
            // Darwin reports ru_maxrss in bytes. This is the app test host's
            // high-water mark, separate from the WebKit helper cohort.
            return Int(usage.ru_maxrss)
        }

        private func sha256(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        private func fixtureDirectory() throws -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExportBudgetCalibration-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let pixel = try #require(Data(base64Encoded: Self.pixelBase64))
            try pixel.write(to: root.appendingPathComponent("pixel.png"))
            return root
        }

        @Test func repeatedImageHTMLUsesActualExportService() async throws {
            _ = try outputDirectory()
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("repeated.html")
            let source = "# Repeated image export\n\n" + String(repeating: "![pixel](pixel.png)\n\n", count: 2048)
            let sourceURL = root.appendingPathComponent("source.md")
            try Data(source.utf8).write(to: sourceURL)
            let request = try ExportRequest(
                text: source, sourceGeneration: 1, theme: BundledThemes.light,
                documentURL: sourceURL,
                resourceAccess: ExportResourceAccess(openingDirectory: root)
            )
            let started = ProcessInfo.processInfo.systemUptime
            _ = try await ExportService.exportHTML(request, to: .html(url: destination, mode: .selfContained))
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let data = try Data(contentsOf: destination)
            let html = try #require(String(data: data, encoding: .utf8))
            #expect(html.components(separatedBy: "data:image/png;base64,").count == 2049)
            #expect(html.contains("Repeated image export"))
            try record("html", values: [
                "case": "actual-self-contained-html", "source_bytes": source.utf8.count,
                "source_sha256": sha256(Data(source.utf8)), "resource_occurrences": 2048,
                "output_bytes": data.count, "output_sha256": sha256(data),
                "elapsed_seconds": elapsed, "app_peak_rss_bytes": peakResidentBytes(),
            ])
        }

        @Test func realWebKitPrintAndPDFKitReadback() async throws {
            _ = try outputDirectory()
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("print.pdf")
            var source = "# BUDGET_START\n\n![pixel](pixel.png)\n\n"
            for section in 1 ... 25 {
                source += "## Section \(section)\n\n"
                source += String(repeating: "Bounded calibration text for real PDF pagination. ", count: 12)
                source += "\n\n"
            }
            source += "## BUDGET_END\n\nFinal text.\n"
            let sourceURL = root.appendingPathComponent("source.md")
            try Data(source.utf8).write(to: sourceURL)
            let request = try ExportRequest(
                text: source, sourceGeneration: 1, theme: BundledThemes.light,
                documentURL: sourceURL,
                resourceAccess: ExportResourceAccess(openingDirectory: root)
            )
            let started = ProcessInfo.processInfo.systemUptime
            let prepared = try await ExportService.prepare(request, target: .pdf(url: destination))
            let preparedSeconds = ProcessInfo.processInfo.systemUptime - started
            let html = try await PDFExportAdapter.hardenedHTML(from: prepared)
            let printStarted = ProcessInfo.processInfo.systemUptime
            try await PDFExportAdapter.export(prepared, to: destination)
            let printSeconds = ProcessInfo.processInfo.systemUptime - printStarted
            let data = try Data(contentsOf: destination)
            let pdf = try #require(PDFDocument(data: data))
            let text = pdf.string ?? ""
            #expect(pdf.pageCount > 1)
            #expect(text.contains("BUDGET_START"))
            #expect(text.contains("BUDGET_END"))
            try record("pdf", values: [
                "case": "actual-webkit-print-pdfkit", "source_bytes": source.utf8.count,
                "source_sha256": sha256(Data(source.utf8)), "prepared_html_bytes": html.utf8.count,
                "pdf_bytes": data.count, "pdf_sha256": sha256(data), "page_count": pdf.pageCount,
                "prepare_seconds": preparedSeconds, "print_and_validation_seconds": printSeconds,
                "app_peak_rss_bytes": peakResidentBytes(),
            ])
        }

        @Test func oversizedSourceIsRefusedBeforePublication() async throws {
            _ = try outputDirectory()
            let root = try fixtureDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("oversized.html")
            let source = String(repeating: "x", count: Self.sourceLimit + 1)
            let request = ExportRequest(text: source, sourceGeneration: 1, theme: BundledThemes.light)
            let started = ProcessInfo.processInfo.systemUptime
            do {
                _ = try await ExportService.exportHTML(request, to: .html(url: destination, mode: .selfContained))
                Issue.record("The production source gate admitted an over-limit document")
            } catch ExportError.budgetExceeded {
                #expect(!FileManager.default.fileExists(atPath: destination.path))
                try record("refusal", values: [
                    "case": "actual-source-cap-plus-one-refusal", "source_bytes": source.utf8.count,
                    "source_sha256": sha256(Data(source.utf8)), "output_exists": false,
                    "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started,
                    "app_peak_rss_bytes": peakResidentBytes(),
                ])
            }
        }
    }

    private enum CalibrationError: Error {
        case unownedHost
        case residentSampleFailed
    }
#endif
