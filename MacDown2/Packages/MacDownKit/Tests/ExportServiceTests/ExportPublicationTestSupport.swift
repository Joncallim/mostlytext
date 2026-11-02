import Darwin
@testable import ExportService
import Foundation

/// Private synthetic filesystem ownership; never uses a real document/profile.
enum ExportPublicationTestSupport {
    struct Fixture: Sendable {
        let directory: URL
        var primary: URL {
            directory.appendingPathComponent("report.html")
        }

        var assets: URL {
            directory.appendingPathComponent("report.assets", isDirectory: true)
        }

        var target: ExportTarget {
            .html(url: primary, mode: .standalone(style: .embedded))
        }
    }

    static func fixture() throws -> Fixture {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-publication-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Fixture(directory: url)
    }

    static func prepared(bytes: Data = Data([0x89, 0x50, 0x4E, 0x47]),
                         text: String = "body") throws -> PreparedExportDocument {
        let resource = ExportResource(
            identity: ExportResourceIdentity(bytes: bytes, mimeType: "image/png"),
            bytes: bytes
        )
        return try ExportSlotTestSupport.registeringGeneratedImages(PreparedExportDocument(
            title: "", bodyHTML: "<p>\(text)</p><img src=\"report.assets/\(resource.identity.fileName)\">",
            stylesheet: "body { color: black; }", manifest: ExportManifest(resources: [resource], referenceMap: [:]),
            diagnostics: [], sourceGeneration: 1, preservesRawHTML: false
        ))
    }

    static func openDirectory(_ url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ExportError.invalidDestination(url.path) }
        return descriptor
    }
}
