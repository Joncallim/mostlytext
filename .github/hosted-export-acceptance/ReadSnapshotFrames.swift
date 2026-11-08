import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import WebKit

/// Fixed hosted mechanism comparison; never product or ordinary-menu acceptance.
@main
@MainActor
struct ReadSnapshotFrames {
    static func main() async throws {
        let root = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-focus")
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == "Joncallim/mostlytext",
              ProcessInfo.processInfo.environment["RUNNER_ARCH"] == "ARM64",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              getuid() == 501, geteuid() == getuid(), let account = getpwuid(getuid()),
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              !FileManager.default.fileExists(atPath: "/Users/jonathanlim"),
              !FileManager.default.fileExists(atPath: "/Users/mostlytexttest"),
              !FileManager.default.fileExists(atPath: "/Volumes/Fast SSD"),
              root.resolvingSymlinksInPath() == root, CommandLine.arguments.count == 1
        else { throw Failure.refused }
        let input = try Data(contentsOf: root.appendingPathComponent("original.html"))
        guard input.count == 6978,
              sha(input) == "7e6cab53fe7ce75713efb9d50aa15c685f8824b8ff59428a8d16930ec70d2d17",
              let html = String(data: input, encoding: .utf8), html.components(separatedBy: "<head>").count == 2
        else { throw Failure.refused }
        let csp = "<meta http-equiv=\"Content-Security-Policy\" content=\""
            + "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
            + "img-src data:; media-src data:; font-src data:; connect-src 'none'; "
            + "object-src 'none'; form-action 'none'; base-uri 'none';\">"
        let lockedHTML = html.replacingOccurrences(of: "<head>", with: "<head>" + csp)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let info = NSPrintInfo()
        let printableWidth = info.paperSize.width - info.leftMargin - info.rightMargin
        let printableHeight = info.paperSize.height - info.topMargin - info.bottomMargin
        guard printableWidth.isFinite, printableHeight.isFinite,
              printableWidth > 0, printableHeight > 0 else { throw Failure.refused }
        guard let viewport = PDFSnapshotFallback.viewportSize(for: info) else { throw Failure.refused }
        let paperHeight = viewport.height
        guard paperHeight.isFinite, (1 ... 10000).contains(paperHeight) else { throw Failure.refused }
        var rows: [[String: Any]] = []
        for (name, height) in [("original", CGFloat(1123)), ("paper", paperHeight), ("minimal", CGFloat(1))] {
            try await rows.append(captureCase(name: name, height: height, info: info, html: lockedHTML, root: root))
            let result: [String: Any] = [
                "diagnostic_only": true, "qualification_candidate": false,
                "input_sha256": sha(input), "paper_size": [info.paperSize.width, info.paperSize.height],
                "margins": [info.leftMargin, info.rightMargin, info.topMargin, info.bottomMargin],
                "completed_cases": rows, "scope": "Fixed WebKit snapshot canvas mechanism only; " +
                    "not historical generation-path cause, production geometry policy or ordinary-export acceptance",
            ]
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
                .write(to: root.appendingPathComponent("snapshot-frame-observations.json"))
        }
    }

    private static func captureCase(
        name: String, height: CGFloat, info: NSPrintInfo, html: String, root: URL
    ) async throws -> [String: Any] {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: height), configuration: configuration)
        let loader = SnapshotNavigation()
        view.navigationDelegate = loader
        try await loader.load(html, in: view)
        let snapshot: Data = try await withCheckedThrowingContinuation { continuation in
            view.createPDF(configuration: WKPDFConfiguration()) { continuation.resume(with: $0) }
        }
        guard !snapshot.isEmpty, snapshot.count <= 4 * 1024 * 1024,
              let source = PDFDocument(data: snapshot), source.pageCount == 1,
              let page = source.page(at: 0) else { throw Failure.refused }
        try snapshot.write(to: root.appendingPathComponent("\(name)-snapshot.pdf"))
        let output = root.appendingPathComponent("\(name)-paginated.pdf")
        try PDFSnapshotFallback.paginate(snapshot, printInfo: info, to: output, maxBytes: 4 * 1024 * 1024)
        let data = try Data(contentsOf: output)
        let pages = try readOutput(data, name: name, root: root)
        let box = page.bounds(for: .mediaBox)
        let row: [String: Any] = [
            "case": name, "view_height": height, "snapshot_sha256": sha(snapshot),
            "snapshot_bytes": snapshot.count, "snapshot_media_box": [box.minX, box.minY, box.width, box.height],
            "paginated_sha256": sha(data), "paginated_bytes": data.count, "pages": pages,
        ]
        view.stopLoading()
        view.navigationDelegate = nil
        return row
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readOutput(_ data: Data, name: String, root: URL) throws -> [[String: Any]] {
        guard let document = PDFDocument(data: data), (1 ... 10).contains(document.pageCount),
              let provider = CGDataProvider(data: data as CFData), let graphics = CGPDFDocument(provider),
              graphics.numberOfPages == document.pageCount else { throw Failure.refused }
        return try (0 ..< document.pageCount).map { index in
            guard let page = document.page(at: index), let graphicsPage = graphics.page(at: index + 1) else {
                throw Failure.refused
            }
            let text = page.string ?? ""
            guard text.utf8.count <= 16384 else { throw Failure.refused }
            let ink = try raster(graphicsPage, to: root.appendingPathComponent("\(name)-page-\(index + 1).png"))
            return ["index": index, "raw_text": text, "actual_raster_nonwhite_pixels": ink]
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
            else { throw Failure.refused }
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
            else { throw Failure.refused }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.refused }
            let samples = storage.bindMemory(to: UInt8.self)
            return stride(from: 0, to: samples.count, by: 4).reduce(0) { total, index in
                total + (min(samples[index], samples[index + 1], samples[index + 2]) < 245 ? 1 : 0)
            }
        }
    }

    enum Failure: Error { case refused }
}

@MainActor
private final class SnapshotNavigation: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in view: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        finish(nil)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
