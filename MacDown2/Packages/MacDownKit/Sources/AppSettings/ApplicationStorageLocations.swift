import Foundation

/// Runtime storage selected only after the required installation transaction.
/// Package convenience defaults remain historical; the app injects this value.
public struct ApplicationStorageLocations: Sendable, Equatable {
    public static let applicationDomain = "app.mostlytext.MostlyText"
    public static let workspaceDomain = applicationDomain + ".workspace"
    public static let developmentDomain = "com.joncallim.MacDown2"
    public static let developmentWorkspaceDomain = "com.joncallim.macdown2.workspace"

    public let dataDirectory: URL
    public let preservedDirectory: URL
    public var session: URL {
        dataDirectory.appendingPathComponent("session.json")
    }

    public var recovery: URL {
        dataDirectory.appendingPathComponent("Recovery", isDirectory: true)
    }

    public var themes: URL {
        dataDirectory.appendingPathComponent("Themes", isDirectory: true)
    }

    public var snippets: URL {
        dataDirectory.appendingPathComponent("snippets.json")
    }

    public var commands: URL {
        dataDirectory.appendingPathComponent("Commands", isDirectory: true)
    }

    public init(dataDirectory: URL, preservedDirectory: URL) {
        self.dataDirectory = dataDirectory
        self.preservedDirectory = preservedDirectory
    }
}
