import CryptoKit
import Darwin
import Foundation

/// A producer-scoped codec. Callers still hold the producer lock and recheck
/// its authority before filesystem mutations; possessing a model is insufficient.
struct ExportCompanionAuthentication {
    struct AuthenticatedReceipt {
        let value: ExportJournalRecord.Receipt
        fileprivate init(_ value: ExportJournalRecord.Receipt) {
            self.value = value
        }
    }

    struct AuthenticatedInventory {
        let value: ExportCompanionInventoryRecord
        let metadataReceipt: AuthenticatedReceipt

        fileprivate init(_ value: ExportCompanionInventoryRecord, metadata: ExportOwnedFileReceipt) {
            self.value = value
            metadataReceipt = AuthenticatedReceipt(ExportJournalRecord.Receipt(metadata))
        }

        func receipt(named name: String) throws -> AuthenticatedReceipt {
            guard let entry = value.owned.first(where: { $0.name == name }) else {
                throw ExportError.unsafePublication
            }
            return AuthenticatedReceipt(entry.receipt)
        }
    }

    private struct Envelope: Codable {
        let payload: Data
        let authentication: Data
    }

    private let key: SymmetricKey
    private let binding: ExportJournalRecord.Binding
    private static let inventoryDomain = Data("MostlyText.Export.CompanionInventory.v1\0".utf8)

    init(keyBytes: Data, binding: ExportJournalRecord.Binding) throws {
        guard keyBytes.count == 32 else { throw ExportError.unsafePublication }
        key = SymmetricKey(data: keyBytes)
        self.binding = binding
    }

    func seal(_ record: ExportCompanionInventoryRecord) throws -> Data {
        try record.validate(binding: binding)
        let encoder = Self.encoder()
        let payload = try encoder.encode(record)
        guard payload.count <= ExportCompanionLimits.payloadBytes else { throw ExportError.unsafePublication }
        let code = HMAC<SHA256>.authenticationCode(for: Self.inventoryDomain + payload, using: key)
        let bytes = try encoder.encode(Envelope(payload: payload, authentication: Data(code)))
        guard bytes.count <= ExportCompanionLimits.envelopeBytes else { throw ExportError.unsafePublication }
        return bytes
    }

    func open(
        _ bytes: Data,
        metadata: ExportPublicationFilesystem.Stamp,
        directory: ExportPublicationFilesystem.Stamp
    ) throws -> AuthenticatedInventory {
        guard bytes.count <= ExportCompanionLimits.envelopeBytes,
              metadata.kind == mode_t(S_IFREG), metadata.size == bytes.count
        else { throw ExportError.unsafePublication }
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard envelope.payload.count <= ExportCompanionLimits.payloadBytes,
              HMAC<SHA256>.isValidAuthenticationCode(
                  envelope.authentication, authenticating: Self.inventoryDomain + envelope.payload, using: key
              )
        else { throw ExportError.unsafePublication }
        // No receipt/binding fields are decoded until authentication succeeds.
        let record = try JSONDecoder().decode(ExportCompanionInventoryRecord.self, from: envelope.payload)
        try record.validate(binding: binding)
        guard record.metadata.sameFile(as: metadata), record.directory.sameDirectory(as: directory)
        else { throw ExportError.unsafePublication }
        return try AuthenticatedInventory(record, metadata: ExportOwnedFileReceipt(bytes: bytes, stamp: metadata))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
