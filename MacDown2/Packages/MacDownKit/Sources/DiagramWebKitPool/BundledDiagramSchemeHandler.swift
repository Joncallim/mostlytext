import Foundation
import WebKit

/// Serves an explicit, fixed set of app-bundled diagram resources to one page.
/// No request path is ever interpreted as a filesystem path.
@MainActor
final class BundledDiagramSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mostlytext-diagram"
    static let host = "bundle"

    private let resources: [String: URL]
    private let allowedDirectory: URL
    private var active = Set<ObjectIdentifier>()

    init?(bundle: Bundle, allowedDirectory: URL, names: Set<String>) {
        guard !names.isEmpty else { return nil }
        var resources: [String: URL] = [:]
        for name in names {
            guard !name.isEmpty, name != ".", name != "..",
                  !name.contains("/"), !name.contains("\\"),
                  let url = bundle.resourceURL?.appendingPathComponent(name),
                  DiagramNavigationPolicy.allows(url, within: allowedDirectory),
                  FileManager.default.isReadableFile(atPath: url.path)
            else { return nil }
            resources[name] = url
        }
        self.resources = resources
        self.allowedDirectory = allowedDirectory
    }

    static func url(for name: String) -> URL? {
        // All names are validated fixed bundle basenames, never authored input.
        URL(string: "\(scheme)://\(host)/\(name)")
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject)
        active.insert(id)
        guard let url = task.request.url,
              url.scheme == Self.scheme,
              url.host == Self.host,
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              let resource = resources[String(url.path.dropFirst())],
              url.path == "/\(resource.lastPathComponent)",
              DiagramNavigationPolicy.allows(resource, within: allowedDirectory)
        else {
            fail(task, id: id)
            return
        }
        do {
            let data = try Data(contentsOf: resource, options: .mappedIfSafe)
            guard active.contains(id) else { return }
            let mimeType: String
            switch resource.pathExtension {
            case "html": mimeType = "text/html"
            case "js": mimeType = "text/javascript"
            case "wasm": mimeType = "application/wasm"
            default: fail(task, id: id); return
            }
            task.didReceive(URLResponse(
                url: url, mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: mimeType == "application/wasm" ? nil : "utf-8"
            ))
            guard active.contains(id) else { return }
            task.didReceive(data)
            guard active.remove(id) != nil else { return }
            task.didFinish()
        } catch {
            fail(task, id: id)
        }
    }

    func webView(_: WKWebView, stop task: any WKURLSchemeTask) {
        active.remove(ObjectIdentifier(task as AnyObject))
    }

    private func fail(_ task: any WKURLSchemeTask, id: ObjectIdentifier) {
        guard active.remove(id) != nil else { return }
        task.didFailWithError(URLError(.fileDoesNotExist))
    }
}
