import Foundation

/// A user-bin symlink still loads the catalogue from the actual enclosing app.
/// Package tests and unbundled builds use SwiftPM's normal resource accessor.
enum CommandLineLocalization {
    static let bundle: Bundle = {
        if let application = try? EmbeddedCommandApplication.current(),
           let bundle = Bundle(url: application.bundleURL
               .appendingPathComponent("Contents/Resources/MacDownKit_CommandLineSupport.bundle")) {
            return bundle
        }
        return .module
    }()
}
