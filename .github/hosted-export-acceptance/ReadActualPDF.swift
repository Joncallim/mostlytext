import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Read-only diagnosis of the exact failed ordinary-export canary, never qualification.
@main
struct ReadActualExportPDF {
    static func main() throws {
        let root = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-focus")
        let input = root.appendingPathComponent("documents/ordinary-export.pdf")
        try checkHost(input: input)
        let data = try Data(contentsOf: input)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              CommandLine.arguments.count == 1, data.count == 16424,
              digest == "ce2b5cc91a8a774c894c43d0f1fe56d4f95cce32171a80c8c2b0f70785af0ae6",
              let document = PDFDocument(data: data), (1 ... 10).contains(document.pageCount),
              let provider = CGDataProvider(data: data as CFData), let graphics = CGPDFDocument(provider),
              graphics.numberOfPages == document.pageCount
        else { throw Refusal.invalid }
        let text = document.string
        guard (text?.utf8.count ?? 0) <= 10 * 16384 else { throw Refusal.invalid }
        let pages = try readPages(document: document, graphics: graphics, root: root)
        let boundsValid = pages.count == document.pageCount
        let result: [String: Any] = [
            "diagnostic_only": true, "qualification_candidate": false,
            "original_source": "734db2f2cd083c040365919134163b55ed57f41f", "original_run": 42_424_848_502,
            "bytes": data.count, "sha256": digest, "pages": pages,
            "raw_document_text": text as Any? ?? NSNull(),
            "original_guard_predicates": [
                "nonempty": !data.isEmpty, "under_16MiB": data.count < 16 * 1024 * 1024,
                "pdf_signature": data.starts(with: Data("%PDF-".utf8)), "PDFDocument": true,
                "one_to_ten_pages": (1 ... 10).contains(document.pageCount), "document_text_present": text != nil,
                "exact_raw_canary": text?.contains("NATIVE_EXPORT_CANARY") ?? false,
                "all_page_bounds_present_positive_finite": boundsValid,
            ],
            "scope": "Exact original bytes and actual PDFKit/raw/visible-media-box/raster observations only; " +
                "no export acceptance, historical generation-path cause, normal Quit or final signed-artifact claim",
        ]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
        try bytes.write(to: root.appendingPathComponent("actual-pdf-readback.json"))
        print("Actual original PDF readback retained; diagnostic only")
    }

    private static func checkHost(input: URL) throws {
        let account = getpwuid(getuid())
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              ProcessInfo.processInfo.environment["RUNNER_OS"] == "macOS",
              let account, String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner", getuid() == 501, getuid() == geteuid(),
              !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
              !FileManager.default.fileExists(atPath: "/Users/mostlytexttest"),
              !FileManager.default.fileExists(atPath: "/Volumes/Fast SSD"),
              input.resolvingSymlinksInPath() == input
        else { throw Refusal.invalid }
    }

    private static func readPages(document: PDFDocument, graphics: CGPDFDocument, root: URL) throws -> [[String: Any]] {
        var pages: [[String: Any]] = []
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index), let graphicsPage = graphics.page(at: index + 1) else {
                throw Refusal.invalid
            }
            let bounds = page.bounds(for: .mediaBox)
            let pageText = page.string ?? ""
            let visibleSelection = page.selection(for: bounds)?.string ?? ""
            let attributedText = page.attributedString?.string
            guard (attributedText?.utf8.count ?? 0) <= 16384 else { throw Refusal.invalid }
            guard pageText.utf8.count <= 16384, visibleSelection.utf8.count <= 16384,
                  bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0
            else { throw Refusal.invalid }
            var row: [String: Any] = [
                "index": index, "media_box": [bounds.minX, bounds.minY, bounds.width, bounds.height],
                "raw_page_text": pageText, "media_box_selection_text": visibleSelection,
                "attributed_page_text": attributedText as Any? ?? NSNull(),
                "attributed_utf16_count": attributedText.map { ($0 as NSString).length } as Any? ?? NSNull(),
            ]
            row["character_count"] = page.numberOfCharacters
            row["raw_utf16_count"] = (pageText as NSString).length
            row["character_geometry"] = try characterGeometry(page: page, text: pageText)
            row["actual_raster_nonwhite_pixels"] = try raster(
                graphicsPage, to: root.appendingPathComponent("actual-pdf-page-\(index + 1).png")
            )
            pages.append(row)
        }
        return pages
    }

    private static func characterGeometry(page: PDFPage, text: String) throws -> [[String: Any]] {
        let source = text as NSString
        guard page.numberOfCharacters == source.length, source.length <= 16384 else { throw Refusal.invalid }
        return try (0 ..< source.length).map { index in
            let box = page.characterBounds(at: index)
            var row: [String: Any] = [
                "utf16_index": index, "raw_index_text": source.substring(with: NSRange(location: index, length: 1)),
            ]
            let selection = page.selection(for: NSRange(location: index, length: 1))
            let selectionText = selection?.string
            guard (selectionText?.utf8.count ?? 0) <= 256 else { throw Refusal.invalid }
            row["selection_present"] = selection != nil
            row["selection_text"] = selectionText as Any? ?? NSNull()
            if let selection {
                let selectedBox = selection.bounds(for: page)
                if selectedBox.isNull {
                    row["selection_bounds"] = NSNull()
                    row["selection_geometry_state"] = "null"
                } else {
                    guard [selectedBox.minX, selectedBox.minY, selectedBox.width, selectedBox.height]
                        .allSatisfy(\.isFinite) else { throw Refusal.invalid }
                    row["selection_bounds"] = [
                        selectedBox.minX,
                        selectedBox.minY,
                        selectedBox.width,
                        selectedBox.height,
                    ]
                    row["selection_geometry_state"] = selectedBox.isEmpty ? "empty" : "rect"
                }
            } else {
                row["selection_bounds"] = NSNull()
                row["selection_geometry_state"] = "missing"
            }
            if box.isNull {
                row["bounds"] = NSNull()
                row["geometry_state"] = "null"
            } else {
                guard [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) else {
                    throw Refusal.invalid
                }
                row["bounds"] = [box.minX, box.minY, box.width, box.height]
                row["geometry_state"] = box.isEmpty ? "empty" : "rect"
            }
            return row
        }
    }

    private static func raster(_ page: CGPDFPage, to output: URL) throws -> Int {
        let width = 612
        let height = 792
        var pixels = Data(count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { storage in
            guard let base = storage.baseAddress,
                  let context = CGContext(
                      data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { throw Refusal.invalid }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
            context.saveGState()
            context.clip(to: rect)
            context.concatenate(page.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.restoreGState()
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(
                      output as CFURL,
                      UTType.png.identifier as CFString,
                      1,
                      nil
                  )
            else { throw Refusal.invalid }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Refusal.invalid }
            let samples = storage.bindMemory(to: UInt8.self)
            return stride(from: 0, to: samples.count, by: 4).reduce(0) { total, index in
                total + (min(samples[index], samples[index + 1], samples[index + 2]) < 245 ? 1 : 0)
            }
        }
    }

    enum Refusal: Error { case invalid }
}
