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
              permittedOutput(arguments[1])
        else { throw Refusal.invalid }
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        guard !data.isEmpty, data.count < 16 * 1024 * 1024, data.starts(with: Data("%PDF-".utf8)),
              let document = PDFDocument(data: data), (1 ... 10).contains(document.pageCount)
        else { throw Refusal.invalid }
        let pages = try (0 ..< document.pageCount).map { index in
            guard let page = document.page(at: index) else { throw Refusal.invalid }
            return try readPage(page)
        }
        let result: [String: Any] = [
            "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "pages": pages,
            "scope": "Actual ordinary UI-created PDF bytes and PDFKit character selections; " +
                "no final signed-artifact or visual parity acceptance",
        ]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        guard let output = String(data: bytes, encoding: .utf8) else { throw Refusal.invalid }
        print(output)
    }

    private static func permittedOutput(_ path: String) -> Bool {
        if path == "/Users/runner/work/_temp/mostlytext-focus/documents/ordinary-export.pdf" {
            return true
        }
        let environment = ProcessInfo.processInfo.environment
        guard let run = environment["GITHUB_RUN_ID"], !run.isEmpty,
              run.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let temp = environment["TMPDIR"] else { return false }
        let file = URL(fileURLWithPath: path)
        let directory = file.deletingLastPathComponent()
        let parent = directory.deletingLastPathComponent().resolvingSymlinksInPath().path
        let approvedTemp = URL(fileURLWithPath: temp).resolvingSymlinksInPath().path
        guard file.lastPathComponent == "export-canary.pdf",
              directory.lastPathComponent == "MostlyTextAcceptance-" + run,
              parent == approvedTemp
        else { return false }
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              info.st_mode & 0o777 == 0o700 else { return false }
        guard lstat(file.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else { return false }
        return true
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
        return [
            "media_box": media, "raw_page_text": text, "character_count": source.length,
            "character_geometry": rows,
        ]
    }

    private static func rectangle(_ box: CGRect) throws -> [Double] {
        guard !box.isNull, !box.isEmpty, [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite)
        else { throw Refusal.invalid }
        return [box.minX, box.minY, box.width, box.height].map(Double.init)
    }

    enum Refusal: Error { case invalid }
}
