import Foundation

/// The unchanged pinned Viz.js payload shared by the app renderer and the
/// short-lived Quick Look JavaScriptCore child.
public enum GraphvizBundledScript {
    public enum Error: Swift.Error {
        case missingResource
    }

    public static func read() throws -> String {
        guard let url = Bundle.module.url(forResource: "viz-global", withExtension: "js") else {
            throw Error.missingResource
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
