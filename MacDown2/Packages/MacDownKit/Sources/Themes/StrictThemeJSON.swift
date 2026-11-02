import Foundation

/// Detect duplicate (including escaped) keys and excessive nesting before a
/// Foundation decoder can discard that evidence. Input is already byte-bounded.
struct StrictThemeJSON {
    private let bytes: [UInt8]
    private var offset = 0

    static func check(_ data: Data) throws {
        guard String(data: data, encoding: .utf8) != nil else { throw ThemeFileError.invalidJSON }
        var scanner = StrictThemeJSON(bytes: Array(data))
        scanner.whitespace()
        guard scanner.peek == 0x7B else { throw ThemeFileError.invalidJSON }
        try scanner.value(depth: 0)
        scanner.whitespace()
        guard scanner.offset == scanner.bytes.count else { throw ThemeFileError.invalidJSON }
    }

    private var peek: UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    private mutating func whitespace() {
        while let byte = peek, [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
            offset += 1
        }
    }

    private mutating func value(depth: Int) throws {
        whitespace()
        guard let byte = peek else { throw ThemeFileError.invalidJSON }
        switch byte {
        case 0x7B:
            guard depth < 8 else { throw ThemeFileError.excessiveNesting }
            try object(depth: depth + 1)
        case 0x22:
            _ = try string()
        case 0x5B:
            // No array is part of this declarative file schema.
            throw ThemeFileError.invalidJSON
        default:
            let start = offset
            while let byte = peek, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x7D, 0x5D].contains(byte) {
                offset += 1
            }
            guard offset > start else { throw ThemeFileError.invalidJSON }
        }
    }

    private mutating func object(depth: Int) throws {
        offset += 1
        whitespace()
        if peek == 0x7D {
            offset += 1; return
        }
        var keys = Set<String>()
        while true {
            let key = try string()
            guard keys.insert(key).inserted else { throw ThemeFileError.duplicateKey(String(key.prefix(128))) }
            whitespace()
            guard peek == 0x3A else { throw ThemeFileError.invalidJSON }
            offset += 1
            try value(depth: depth)
            whitespace()
            if peek == 0x7D {
                offset += 1; return
            }
            guard peek == 0x2C else { throw ThemeFileError.invalidJSON }
            offset += 1
            whitespace()
        }
    }

    private mutating func string() throws -> String {
        guard peek == 0x22 else { throw ThemeFileError.invalidJSON }
        let start = offset
        offset += 1
        while let byte = peek {
            offset += 1
            if byte == 0x22 {
                do {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start ..< offset]))
                } catch {
                    throw ThemeFileError.invalidJSON
                }
            }
            if byte == 0x5C {
                guard peek != nil else { throw ThemeFileError.invalidJSON }
                offset += 1
            }
        }
        throw ThemeFileError.invalidJSON
    }
}
