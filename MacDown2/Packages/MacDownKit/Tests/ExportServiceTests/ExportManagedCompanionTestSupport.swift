import Darwin
@testable import ExportService
import Foundation
import Testing

final class ExportManagedCompanionFixture {
    let files: ExportPrimaryRecoveryTestSupport.Fixture
    let source: URL
    var target: ExportTarget {
        .html(url: files.primary, mode: .standalone(style: .embedded))
    }

    var assets: URL {
        files.output.appendingPathComponent("report.assets", isDirectory: true)
    }

    init() throws {
        files = try ExportPrimaryRecoveryTestSupport.Fixture()
        source = files.root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
    }

    deinit { files.cleanup() }

    func prepare(_ version: Int, mode: HTMLExportMode = .standalone(style: .embedded),
                 prefix: String = "") async throws -> PreparedExportDocument {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data("image version \(version)".utf8)
        try bytes.write(to: source.appendingPathComponent("image.png"))
        return try await ExportService.prepare(
            ExportRequest(text: prefix + "![image](image.png)\n", sourceGeneration: UInt(version),
                          theme: ExportTestSupport.lightTheme(),
                          resourceAccess: ExportResourceAccess(openingDirectory: source)),
            target: .html(url: files.primary, mode: mode)
        )
    }

    @discardableResult
    func write(_ prepared: PreparedExportDocument, mode: HTMLExportMode = .standalone(style: .embedded),
               hooks: ExportPublicationHooks = .init()) throws -> ExportResult {
        try ExportFileWriter.writeHTML(prepared, to: .html(url: files.primary, mode: mode),
                                       hooks: hooks, recovery: files.location)
    }

    func assetNames() throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: assets.path))
    }

    func resourceURL(_ prepared: PreparedExportDocument) throws -> URL {
        try assets.appendingPathComponent(#require(prepared.manifest.resources.first).identity.fileName)
    }

    func assertIdle() throws {
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: files.location.directory.path))
            == ["producer.key", "producer.lock"])
        #expect(try !assetNames().contains(where: { $0.hasPrefix(".mt-") }))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: files.output.path)
            .contains(where: { $0.hasPrefix(".mt-") }))
    }

    func inventory() throws -> ExportCompanionInventoryRecord {
        let producer = try files.store()
        let descriptor = open(assets.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        let name = ExportCompanionInventoryRecord.fileName
        let bytes = try #require(try ExportPublicationFilesystem.readBoundedFile(
            name, in: descriptor, maxBytes: ExportCompanionLimits.envelopeBytes
        ))
        return try producer.companionAuthentication().open(
            bytes, metadata: ExportPublicationFilesystem.childStamp(name, in: descriptor),
            directory: ExportPublicationFilesystem.directoryStamp(descriptor)
        ).value
    }
}
