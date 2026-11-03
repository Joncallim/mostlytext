import CryptoKit
import Darwin
import Foundation

struct ExportRetentionLimit {
    let files: Int
    let bytes: Int
    static let standard = Self(files: ExportResourceBudget.standard.maxResourceCount + 1,
                               bytes: ExportResourceBudget.standard.maxAggregateResourceBytes)
}

struct ExportPublicationHooks {
    var afterCompanionDirectoryOpened: (() -> Void)?
    var afterPrimaryStaged: (() -> Void)?
    var beforePromotion: (() -> Void)?
    var beforeJournalFinalization: (() throws -> Void)?
    var retentionLimit = ExportRetentionLimit.standard
}

/// Conservative retention: never delete old assets or adopt unknown files.
/// All flat entries count toward the ceiling, including unknown user files.
/// Ambiguous interrupted staging blocks growth until deliberately recovered.
enum ExportPublicationRetention {
    struct Retained {
        var names: Set<Data> = []
        var bytes = 0

        mutating func reserve(name: String, bytes incoming: Int, limits: ExportRetentionLimit) throws {
            let key = Data(name.utf8)
            guard !names.contains(key) else { return }
            guard names.count < limits.files, incoming >= 0, limits.bytes >= 0, incoming <= limits.bytes,
                  bytes <= limits.bytes - incoming else { throw tooLarge }
            names.insert(key)
            bytes += incoming
        }
    }

    static var tooLarge: ExportError {
        .budgetExceeded(String(localized: "retained export assets exceed the safety limit", bundle: .module))
    }

    static func scratchPrefix(for primary: String) -> String {
        let digest = SHA256.hash(data: Data(primary.utf8)).map { String(format: "%02x", $0) }.joined()
        return ".mt-" + digest + "-"
    }

    static func checkParent(_ descriptor: Int32, scratchPrefix: String) throws {
        try enumerate(descriptor, maximum: 65536) { name in
            guard !name.hasPrefix(scratchPrefix) else { throw ExportError.unsafePublication }
        }
    }

    static func scanAssets(_ descriptor: Int32, limits: ExportRetentionLimit) throws -> Retained {
        var result = Retained()
        try enumerate(descriptor, maximum: limits.files) { name in
            guard !name.hasPrefix(".mt-") else { throw ExportError.unsafePublication }
            let stamp = try ExportPublicationFilesystem.childStamp(name, in: descriptor)
            let bytes = stamp.kind == mode_t(S_IFREG) ? Int(exactly: stamp.size) : 0
            guard let bytes, bytes >= 0 else { throw tooLarge }
            try result.reserve(name: name, bytes: bytes, limits: limits)
        }
        return result
    }

    private static func enumerate(_ descriptor: Int32, maximum: Int, inspect: (String) throws -> Void) throws {
        let copied = dup(descriptor)
        guard copied >= 0 else { throw ExportPublicationFilesystem.posixFailure() }
        guard let directory = fdopendir(copied) else {
            _ = Darwin.close(copied)
            throw ExportPublicationFilesystem.posixFailure()
        }
        defer { closedir(directory) }
        var count = 0
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw ExportPublicationFilesystem.posixFailure() }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) {
                String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8)
            }
            guard let name else { throw ExportError.unsafePublication }
            if name == "." || name == ".." {
                continue
            }
            count += 1
            guard count <= maximum else { throw tooLarge }
            try inspect(name)
        }
    }
}
