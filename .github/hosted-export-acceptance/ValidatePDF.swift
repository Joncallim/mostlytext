import CryptoKit
import Darwin
import Foundation
import PDFKit

@main
struct ValidateActualExportPDF {
    static func main() throws {
        let arguments = CommandLine.arguments
        let account = getpwuid(getuid())
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              let account, String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner", getuid() == 501, getuid() == geteuid(),
              arguments.count == 2,
              arguments[1] == "/Users/runner/work/_temp/mostlytext-focus/documents/ordinary-export.pdf"
        else { throw Refusal.invalid }
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        guard !data.isEmpty, data.count < 16 * 1024 * 1024, data.starts(with: Data("%PDF-".utf8)),
              let document = PDFDocument(data: data), (1 ... 10).contains(document.pageCount),
              let text = document.string, text.contains("NATIVE_EXPORT_CANARY")
        else { throw Refusal.invalid }
        let bounds = (0 ..< document.pageCount).compactMap { document.page(at: $0)?.bounds(for: .mediaBox) }
        guard bounds.count == document.pageCount,
              bounds.allSatisfy({ $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 })
        else { throw Refusal.invalid }
        let result: [String: Any] = [
            "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "pages": document.pageCount, "actual_text_contains_canary": true,
            "bounds": bounds.map { ["width": $0.width, "height": $0.height] },
            "scope": "Actual ordinary UI-created PDF bytes/text/pages; " +
                "no final signed-artifact or visual parity acceptance",
        ]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        guard let output = String(data: bytes, encoding: .utf8) else { throw Refusal.invalid }
        print(output)
    }

    enum Refusal: Error { case invalid }
}
