import Foundation

/// The byte-order-mark policy of a file's decoded text.
///
/// Captured with the immutable byte snapshot so writes can reproduce the
/// exact on-disk byte prefix, and so session restore can re-interpret text
/// without re-reading the file.
public enum FileBOM: String, Sendable, Equatable, Codable {
    case none
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}

/// The decoding metadata carried with a document's text.
///
/// `encodingRawValue` is the `String.Encoding.rawValue` used to decode the
/// bytes; `bom` records the byte-order mark that was present (or absent).
public struct FileEncodingMetadata: Sendable, Equatable, Hashable, Codable {
    public let encodingRawValue: UInt
    public let bom: FileBOM

    public init(encodingRawValue: UInt, bom: FileBOM) {
        self.encodingRawValue = encodingRawValue
        self.bom = bom
    }

    public init(encoding: String.Encoding, bom: FileBOM) {
        self.init(encodingRawValue: encoding.rawValue, bom: bom)
    }

    /// Decodes session JSON. Unknown or mutually inconsistent
    /// `encodingRawValue`/`bom` pairs (a corrupted or hand-edited session) are
    /// replaced with the documented default (UTF-8, no BOM) instead of
    /// carrying garbage metadata into restore, where it would only surface
    /// later as a failed save — or, for a mismatched pair, as bytes written
    /// under the wrong prefix.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(UInt.self, forKey: .encodingRawValue)
        let bom = try container.decode(FileBOM.self, forKey: .bom)
        if Self.consistentEncoding(for: rawValue, bom: bom) != nil {
            self.init(encodingRawValue: rawValue, bom: bom)
        } else {
            self = .utf8Default
        }
    }

    /// The encoding a BOM kind may pair with; `nil` for inconsistent pairs.
    /// A BOM implies its own encoding; without a BOM any encoding the app
    /// can read and write (`FileEncodingCatalog`) is valid.
    static func consistentEncoding(for rawValue: UInt, bom: FileBOM) -> String.Encoding? {
        switch bom {
        case .none:
            FileEncodingCatalog.isSupported(rawValue: rawValue) ? String.Encoding(rawValue: rawValue) : nil
        case .utf8:
            rawValue == String.Encoding.utf8.rawValue ? .utf8 : nil
        case .utf16LittleEndian:
            rawValue == String.Encoding.utf16LittleEndian.rawValue ? .utf16LittleEndian : nil
        case .utf16BigEndian:
            rawValue == String.Encoding.utf16BigEndian.rawValue ? .utf16BigEndian : nil
        }
    }

    /// Whether `FileStore`'s automatic decode can reproduce this metadata
    /// from the bytes alone: UTF-8 with or without a BOM, or UTF-16 with its
    /// own BOM. Everything else (a legacy encoding, or BOM-less UTF-16) was
    /// chosen explicitly and must be re-decoded explicitly, or an external
    /// reload would fail or silently revert the choice.
    public var isAutomaticallyDetectable: Bool {
        switch (bom, encodingRawValue) {
        case (.none, String.Encoding.utf8.rawValue),
             (.utf8, String.Encoding.utf8.rawValue),
             (.utf16LittleEndian, String.Encoding.utf16LittleEndian.rawValue),
             (.utf16BigEndian, String.Encoding.utf16BigEndian.rawValue):
            true
        default:
            false
        }
    }

    /// How to decode this document's bytes when they are re-read from disk.
    public var decodingPolicy: FileDecodingPolicy {
        isAutomaticallyDetectable ? .automatic : .explicit(encoding)
    }

    /// The encoding used to decode the text.
    public var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    /// The documented default for new documents and legacy/malformed session
    /// metadata: UTF-8 without a BOM.
    public static let utf8Default = FileEncodingMetadata(encoding: .utf8, bom: .none)
}

/// How `FileStore` interprets bytes.
public enum FileDecodingPolicy: Sendable, Equatable {
    /// UTF-8 BOM, UTF-16 BOM, then strict UTF-8. Never guesses.
    case automatic
    /// The caller chose `encoding`. Decoding is lossless or it fails: the
    /// text must re-encode to exactly the bytes read, so saving unchanged
    /// text can never alter the file.
    case explicit(String.Encoding)
}

/// One decoding problem found in a file's raw bytes.
public struct FileDecodingDiagnostic: Sendable, Equatable {
    public let message: String
    /// Zero-based byte offset into the copied input bytes where the invalid
    /// sequence begins.
    public let byteOffset: Int

    public init(message: String, byteOffset: Int) {
        self.message = message
        self.byteOffset = byteOffset
    }
}

/// The result of decoding a byte snapshot: the text, the BOM it carried, and
/// the encoding that decoded it. A failed decode yields no text.
public struct FileDecodedPayload: Sendable, Equatable {
    public let text: String
    public let encoding: String.Encoding
    public let bom: FileBOM

    public var metadata: FileEncodingMetadata {
        FileEncodingMetadata(encoding: encoding, bom: bom)
    }
}
