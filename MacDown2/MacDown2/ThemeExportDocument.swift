import Foundation
import SwiftUI
import Themes
import UniformTypeIdentifiers

/// Only immutable admitted theme bytes enter the platform's export workflow.
/// File import uses the bounded descriptor reader instead of FileWrapper input.
struct ThemeExportDocument: SwiftUI.FileDocument {
    static let contentType = UTType(exportedAs: "app.mostlytext.theme", conformingTo: .json)
    static var readableContentTypes: [UTType] {
        [contentType]
    }

    let data: Data

    init(theme: ThemeFile) throws {
        data = try theme.encoded()
    }

    init(configuration _: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func suggestedName(_ displayName: String) -> String {
        let sanitized = displayName.components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var result = ""
        for character in sanitized {
            let next = result + String(character)
            if next.utf8.count > 200 {
                break
            }
            result = next
        }
        return result.isEmpty ? String(localized: "Theme") : result
    }
}
