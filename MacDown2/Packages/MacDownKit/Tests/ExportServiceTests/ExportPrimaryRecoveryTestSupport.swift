import CryptoKit
import Darwin
@testable import ExportService
import Foundation
import Testing

enum ExportPrimaryRecoveryTestSupport {
    final class Fixture {
        let root: URL
        let output: URL
        let location: ExportRecoveryLocation
        let directory: ExportPublicationFilesystem.DirectoryHandle
        let old = Data("previous primary".utf8)
        let desired = Data("desired primary".utf8)
        let leaf = "report.html"

        var primary: URL {
            output.appendingPathComponent(leaf)
        }

        var descriptor: Int32 {
            directory.descriptor
        }

        var recordURL: URL {
            get throws {
                let binding = try ExportJournalRecord.Binding(
                    parent: ExportPublicationFilesystem.directoryStamp(descriptor), leaf: leaf
                )
                return try location.directory.appendingPathComponent(binding.fileName)
            }
        }

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("export-primary-recovery-\(UUID())", isDirectory: true)
            output = root.appendingPathComponent("output", isDirectory: true)
            location = ExportRecoveryLocation(directory: root.appendingPathComponent("private", isDirectory: true))
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let descriptor = open(output.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try #require(descriptor >= 0)
            directory = ExportPublicationFilesystem.DirectoryHandle(descriptor)
        }

        func store(leaf: String? = nil) throws -> ExportJournalStore {
            try ExportJournalStore(location: location,
                                   parent: ExportPublicationFilesystem.directoryStamp(descriptor),
                                   leaf: leaf ?? self.leaf)
        }

        @discardableResult
        func stage(prior: Data? = nil) throws -> String {
            if let prior {
                try prior.write(to: primary)
            }
            let name = ExportPublicationRetention.scratchPrefix(for: leaf) + UUID().uuidString + ".html.tmp"
            let store = try store()
            try ExportPublicationFilesystem.withScratch(desired, name: name, in: descriptor,
                                                        retainOnSuccess: true) { _, stamp in
                try store.begin(priorDigest: prior.map { Data(SHA256.hash(data: $0)) },
                                desired: Data(SHA256.hash(data: desired)), name: name,
                                receipt: ExportOwnedFileReceipt(bytes: desired, stamp: stamp))
            }
            return name
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
