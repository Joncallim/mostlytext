import Foundation

extension FileStore {
    /// Decodes a byte snapshot into text with its BOM and encoding.
    ///
    /// `.automatic` detection order: UTF-8 BOM, UTF-16 LE/BE BOM, then strict
    /// UTF-8. Malformed input throws `.decodingFailed` with one diagnostic for
    /// the first invalid byte sequence (zero-based byte offset into `data`);
    /// no replacement characters or text snapshot are ever produced.
    func decode(_ data: Data, policy: FileDecodingPolicy = .automatic) throws(FileStoreError) -> FileDecodedPayload {
        switch policy {
        case .automatic:
            if data.starts(with: [0xFF, 0xFE]) {
                return try decodeUTF16(data, encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
            }
            if data.starts(with: [0xFE, 0xFF]) {
                return try decodeUTF16(data, encoding: .utf16BigEndian, bom: .utf16BigEndian)
            }
            return try decodeUTF8(data)
        case let .explicit(encoding):
            return try decodeExplicit(data, as: encoding)
        }
    }

    private func decodeExplicit(_ data: Data,
                                as encoding: String.Encoding) throws(FileStoreError) -> FileDecodedPayload {
        switch encoding {
        case .utf8:
            return try decodeUTF8(data)
        case .utf16LittleEndian:
            if data.starts(with: [0xFE, 0xFF]) {
                throw Self.mismatch("UTF-16 LE", at: 0)
            }
            return try decodeUTF16(
                data,
                encoding: encoding,
                bom: data.starts(with: [0xFF, 0xFE]) ? .utf16LittleEndian : .none
            )
        case .utf16BigEndian:
            if data.starts(with: [0xFF, 0xFE]) {
                throw Self.mismatch("UTF-16 BE", at: 0)
            }
            return try decodeUTF16(
                data,
                encoding: encoding,
                bom: data.starts(with: [0xFE, 0xFF]) ? .utf16BigEndian : .none
            )
        case .utf16:
            guard data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) else {
                throw Self.mismatch("UTF-16", at: 0)
            }
            return try decode(data, policy: .automatic)
        default:
            return try decodeLegacy(data, as: encoding)
        }
    }

    /// Lossless or nothing: the decoded text must re-encode to exactly the
    /// bytes that were read, so saving unchanged text can never alter them.
    private func decodeLegacy(_ data: Data, as encoding: String.Encoding) throws(FileStoreError) -> FileDecodedPayload {
        guard FileEncodingCatalog.isSupported(rawValue: encoding.rawValue) else { throw .encodingDetectionFailed }
        let name = String.localizedName(of: encoding)
        guard let text = String(data: data, encoding: encoding) else { throw Self.mismatch(name, at: 0) }
        let reencoded = text.data(using: encoding, allowLossyConversion: false) ?? Data()
        guard reencoded == data else {
            let offset = zip(data, reencoded).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                ?? min(data.count, reencoded.count)
            throw Self.mismatch(name, at: offset)
        }
        return FileDecodedPayload(text: text, encoding: encoding, bom: .none)
    }

    private static func mismatch(_ name: String, at offset: Int) -> FileStoreError {
        .decodingFailed([
            FileDecodingDiagnostic(
                message: String(localized: "Invalid \(name) byte sequence.", bundle: .module),
                byteOffset: offset
            ),
        ])
    }

    private func decodeUTF8(_ data: Data) throws(FileStoreError) -> FileDecodedPayload {
        let hasBOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        let prefix = hasBOM ? 3 : 0
        // `subdata` (not `dropFirst`): a dropFirst slice keeps its original
        // absolute indices, which traps when re-indexed as a `Data`.
        let payload = hasBOM ? data.subdata(in: 3 ..< data.count) : data
        if let offset = utf8InvalidByteOffset(in: payload) {
            throw .decodingFailed([
                FileDecodingDiagnostic(
                    message: String(localized: "Invalid UTF-8 byte sequence.", bundle: .module),
                    byteOffset: offset + prefix
                ),
            ])
        }
        // The payload was just validated as strict UTF-8, so this decode
        // is guaranteed to succeed.
        return FileDecodedPayload(
            // swiftlint:disable:next optional_data_string_conversion
            text: String(decoding: payload, as: UTF8.self),
            encoding: .utf8,
            bom: hasBOM ? .utf8 : .none
        )
    }

    /// `data` includes its BOM when `bom` is not `.none`.
    private func decodeUTF16(
        _ data: Data,
        encoding: String.Encoding,
        bom: FileBOM
    ) throws(FileStoreError) -> FileDecodedPayload {
        let prefix = bom == .none ? 0 : 2
        let payload = data.subdata(in: prefix ..< data.count)
        guard payload.count.isMultiple(of: 2), let text = String(data: payload, encoding: encoding) else {
            let unitOffset = utf16InvalidUnitOffset(in: payload, littleEndian: encoding == .utf16LittleEndian)
            throw .decodingFailed([
                FileDecodingDiagnostic(
                    message: String(localized: "Invalid UTF-16 byte sequence.", bundle: .module),
                    byteOffset: unitOffset + prefix
                ),
            ])
        }
        return FileDecodedPayload(text: text, encoding: encoding, bom: bom)
    }

    // Returns the byte offset of the first invalid UTF-8 sequence, or `nil`
    // when the payload is well-formed. Overlong encodings, surrogate code
    // points, and values above U+10FFFF are all invalid.
    //
    // The validation is deliberately one linear pass over the payload: each
    // branch checks one UTF-8 rule (lead byte, continuation bytes, overlong
    // form, surrogate range, maximum code point). Splitting the pass would
    // obscure the byte arithmetic, so the complexity budget is documented
    // rather than worked around.
    // swiftlint:disable:next cyclomatic_complexity
    private func utf8InvalidByteOffset(in data: Data) -> Int? {
        var index = 0
        while index < data.count {
            let byte = data[index]
            if byte < 0x80 {
                index += 1
                continue
            }
            let length: Int
            var codePoint: UInt32
            switch byte {
            case 0xC2 ... 0xDF:
                length = 2
                codePoint = UInt32(byte & 0x1F)
            case 0xE0 ... 0xEF:
                length = 3
                codePoint = UInt32(byte & 0x0F)
            case 0xF0 ... 0xF4:
                length = 4
                codePoint = UInt32(byte & 0x07)
            default:
                // Stray continuation byte or invalid lead byte.
                return index
            }
            guard index + length <= data.count else { return index }
            for continuation in 1 ..< length {
                let next = data[index + continuation]
                guard next & 0xC0 == 0x80 else { return index }
                codePoint = (codePoint << 6) | UInt32(next & 0x3F)
            }
            let minimumCodePoint: UInt32 = switch length {
            case 2: 0x80
            case 3: 0x800
            default: 0x10000
            }
            if codePoint < minimumCodePoint {
                return index
            }
            if length == 3, (0xD800 ... 0xDFFF).contains(codePoint) {
                return index
            }
            if length == 4, codePoint > 0x10FFFF {
                return index
            }
            index += length
        }
        return nil
    }

    /// Returns the byte offset (into `data`) of the first invalid UTF-16
    /// sequence: an unpaired surrogate or a truncated/odd trailing unit.
    private func utf16InvalidUnitOffset(in data: Data, littleEndian: Bool) -> Int {
        func unit(at offset: Int) -> UInt16 {
            if littleEndian {
                return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            }
            return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        }
        var index = 0
        while index + 1 < data.count {
            let value = unit(at: index)
            if (0xD800 ... 0xDBFF).contains(value) {
                guard index + 3 < data.count else { return index }
                let next = unit(at: index + 2)
                guard (0xDC00 ... 0xDFFF).contains(next) else { return index }
                index += 4
            } else if (0xDC00 ... 0xDFFF).contains(value) {
                return index
            } else {
                index += 2
            }
        }
        return index
    }
}
