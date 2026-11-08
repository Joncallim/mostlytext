import CryptoKit
import Darwin
import Foundation
import PDFKit

/// Read-only actual selections for two immutable canaries, on the guarded hosted machine only.
@main
struct ReadPlacedPDF {
    static func main() throws {
        let root = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-focus")
        try checkHost(root)
        for (name, size, digest) in [
            ("original", 16424, "ce2b5cc91a8a774c894c43d0f1fe56d4f95cce32171a80c8c2b0f70785af0ae6"),
            ("corrected", 15107, "d95a9e149c236e572551cc6cc913bc044d80822c8a14796a438ce6f5171aab08"),
        ] {
            let input = root.appendingPathComponent(name + ".pdf")
            guard input.resolvingSymlinksInPath() == input else { throw Refusal.invalid }
            let data = try Data(contentsOf: input)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard data.count == size, hash == digest, data.starts(with: Data("%PDF-".utf8)),
                  let document = PDFDocument(data: data), (1 ... 10).contains(document.pageCount)
            else { throw Refusal.invalid }
            let pages = try (0 ..< document.pageCount).map { index in
                guard let page = document.page(at: index) else { throw Refusal.invalid }
                return try readPage(page)
            }
            let result: [String: Any] = ["bytes": data.count, "sha256": hash, "pages": pages]
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
                .write(to: root.appendingPathComponent(name + "-selection.json"))
        }
        print("Both exact PDF selection records retained")
    }

    private static func checkHost(_ root: URL) throws {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              ProcessInfo.processInfo.environment["RUNNER_OS"] == "macOS",
              ProcessInfo.processInfo.environment["RUNNER_ARCH"] == "ARM64",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              CommandLine.arguments.count == 1, getuid() == 501, getuid() == geteuid(),
              let account = getpwuid(getuid()), String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
              !FileManager.default.fileExists(atPath: "/Users/mostlytexttest"),
              !FileManager.default.fileExists(atPath: "/Volumes/Fast SSD"),
              root.resolvingSymlinksInPath() == root else { throw Refusal.invalid }
    }

    private static func readPage(_ page: PDFPage) throws -> [String: Any] {
        let text = page.string ?? ""
        let source = text as NSString
        guard source.length == page.numberOfCharacters, source.length <= 16384 else { throw Refusal.invalid }
        let media = try rectangle(page.bounds(for: .mediaBox))
        let rows: [[String: Any]] = try (0 ..< source.length).map { index in
            let range = NSRange(location: index, length: 1)
            let char = source.substring(with: range)
            var row: [String: Any] = ["utf16_index": index, "raw_index_text": char]
            if char.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return row
            }
            guard let selection = page.selection(for: range), selection.string == char else { throw Refusal.invalid }
            row["selection_present"] = true
            row["selection_text"] = char
            row["selection_geometry_state"] = "rect"
            row["selection_bounds"] = try rectangle(selection.bounds(for: page))
            return row
        }
        return ["media_box": media, "raw_page_text": text, "character_count": source.length, "character_geometry": rows]
    }

    private static func rectangle(_ box: CGRect) throws -> [Double] {
        guard !box.isNull, !box.isEmpty, [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite)
        else { throw Refusal.invalid }
        return [box.minX, box.minY, box.width, box.height].map(Double.init)
    }

    enum Refusal: Error { case invalid }
}
