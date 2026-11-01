import CoreFoundation
import Foundation

/// Schema/semantic validation is separate from decoding so unknown fields and
/// future schemas cannot be silently treated as current theme data.
enum ThemeFileValidation {
    static func validateStructure(_ data: Data) throws {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ThemeFileError.invalidJSON
        }
        let root = try object(raw, path: "theme", required: [
            "schemaVersion", "stableID", "displayName", "appearance", "chrome", "tokenStyles",
        ])
        guard let version = root["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue.isFinite,
              version.doubleValue.rounded(.towardZero) == version.doubleValue else {
            throw ThemeFileError.invalidField("schemaVersion")
        }
        guard version.doubleValue == Double(ThemeFile.currentSchemaVersion) else {
            throw ThemeFileError.unsupportedVersion
        }
        let chrome = try object(root["chrome"] ?? NSNull(), path: "chrome",
                                required: ["background", "foreground", "caret", "selection"],
                                optional: ["currentLine", "invisibles"])
        for (name, color) in chrome {
            try validateColorShape(color, path: "chrome." + name)
        }
        guard let tokens = root["tokenStyles"] as? [String: Any] else {
            throw ThemeFileError.invalidField("tokenStyles")
        }
        guard tokens.count <= ThemeFile.maximumTokenStyles else { throw ThemeFileError.tooManyTokenStyles }
        for (name, value) in tokens {
            let style = try object(value, path: "tokenStyles." + name,
                                   required: ["color"], optional: ["bold", "italic", "underline"])
            try validateColorShape(style["color"] ?? NSNull(), path: "tokenStyles." + name + ".color")
            for flag in ["bold", "italic", "underline"] {
                if let value = style[flag] {
                    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                        throw ThemeFileError.invalidField("tokenStyles." + name + "." + flag)
                    }
                }
            }
        }
    }

    static func validate(_ file: ThemeFile) throws {
        let name = file.displayName
        guard !name.isEmpty, name.unicodeScalars.count <= 80,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ThemeFileError.invalidField("displayName")
        }
        guard file.tokenStyles.count <= ThemeFile.maximumTokenStyles else {
            throw ThemeFileError.tooManyTokenStyles
        }
        let chrome = file.chrome
        let colors: [(String, ThemeColor?)] = [
            ("background", chrome.background), ("foreground", chrome.foreground),
            ("caret", chrome.caret), ("selection", chrome.selection),
            ("currentLine", chrome.currentLine), ("invisibles", chrome.invisibles),
        ]
        for (name, color) in colors {
            if let color {
                try validateColor(color, path: "chrome." + name)
            }
        }
        guard chrome.background.alpha == 1 else { throw ThemeFileError.invalidField("chrome.background.alpha") }
        for (name, style) in file.tokenStyles {
            guard validCapture(name) else { throw ThemeFileError.invalidField("tokenStyles.capture") }
            try validateColor(style.color, path: "tokenStyles." + name + ".color")
        }
    }

    private static func object(
        _ value: Any, path: String, required: Set<String>, optional: Set<String> = []
    ) throws -> [String: Any] {
        guard let values = value as? [String: Any], required.isSubset(of: Set(values.keys)),
              Set(values.keys).isSubset(of: required.union(optional)) else {
            throw ThemeFileError.invalidField(path)
        }
        return values
    }

    private static func validateColorShape(_ value: Any, path: String) throws {
        _ = try object(value, path: path, required: ["red", "green", "blue", "alpha"])
    }

    private static func validateColor(_ color: ThemeColor, path: String) throws {
        guard [color.red, color.green, color.blue, color.alpha].allSatisfy({ $0.isFinite && (0 ... 1).contains($0) })
        else {
            throw ThemeFileError.invalidField(path)
        }
    }

    private static func validCapture(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 96 else { return false }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { byte in
                (97 ... 122).contains(byte) || (48 ... 57).contains(byte) || byte == 95 || byte == 45
            }
        }
    }
}
