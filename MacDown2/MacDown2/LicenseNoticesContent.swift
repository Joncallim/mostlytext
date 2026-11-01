import Foundation

/// The canonical files are bundled by project.yml. No second notice copy or
/// network source is used to populate the native license screen.
struct LicenseNoticesContent: Equatable, Sendable {
    static let maximumResourceBytes = 2 * 1024 * 1024

    enum Failure: Error, Equatable {
        case missingResource
        case oversizedResource
        case invalidText
    }

    let productLicense: String
    let thirdPartyNotices: String

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let license = bundle.url(forResource: "LICENSE", withExtension: nil),
              let notices = bundle.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") else {
            throw Failure.missingResource
        }
        return try Self(product: read(license), notices: read(notices))
    }

    init(product: Data, notices: Data) throws {
        productLicense = try Self.text(product)
        thirdPartyNotices = try Self.text(notices)
    }

    private static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bounded allocation even if a damaged app contains an enormous file.
        var data = Data()
        while data.count <= maximumResourceBytes {
            let remaining = maximumResourceBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(65536, remaining)), !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw Failure.oversizedResource
    }

    private static func text(_ data: Data) throws -> String {
        guard data.count <= maximumResourceBytes else { throw Failure.oversizedResource }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { throw Failure.invalidText }
        return text
    }
}
