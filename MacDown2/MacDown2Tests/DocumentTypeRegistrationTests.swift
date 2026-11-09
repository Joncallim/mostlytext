import FileCore
import Foundation
@testable import MacDown2
import Testing

/// Review pass 5: `toml` was a registered `FileFormat` with an exported UTI but no `CFBundleDocumentTypes` entry, so
/// Finder's Open With, Dock drops and default-app selection never offered the app for `.toml` files.
struct DocumentTypeRegistrationTests {
    @Test func everyRegisteredFormatExtensionIsADeclaredDocumentType() throws {
        let declared = try #require(Bundle(for: AppDelegate.self).object(
            forInfoDictionaryKey: "CFBundleDocumentTypes"
        ) as? [[String: Any]])
        let extensions = Set(declared.flatMap { ($0["CFBundleTypeExtensions"] as? [String]) ?? [] })

        let missing = FileFormatRegistry().formats.flatMap(\.extensions).filter { !extensions.contains($0) }

        #expect(missing.isEmpty, "undeclared extensions: \(missing)")
    }

    @Test func markdownAliasesHaveAConformingRegisteredType() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let documents = try #require(bundle.object(
            forInfoDictionaryKey: "CFBundleDocumentTypes"
        ) as? [[String: Any]])
        let markdown = try #require(documents.first {
            ($0["CFBundleTypeName"] as? String) == "Markdown Document"
        })

        // LSItemContentTypes takes precedence over CFBundleTypeExtensions on macOS.
        // The three non-system aliases therefore need a type with their own tags.
        let contentTypes = (markdown["LSItemContentTypes"] as? [String]) ?? []
        #expect(contentTypes == ["net.daringfireball.markdown", "app.mostlytext.markdown-alias"])
        #expect((markdown["CFBundleTypeRole"] as? String) == "Editor")
        #expect((markdown["LSHandlerRank"] as? String) == "Default")

        let exported = try #require(bundle.object(
            forInfoDictionaryKey: "UTExportedTypeDeclarations"
        ) as? [[String: Any]])
        #expect(!exported.contains {
            ($0["UTTypeIdentifier"] as? String) == "net.daringfireball.markdown"
        }, "the system Markdown type must not be redeclared")
        let alias = try #require(exported.first {
            ($0["UTTypeIdentifier"] as? String) == "app.mostlytext.markdown-alias"
        })
        #expect((alias["UTTypeConformsTo"] as? [String]) == ["net.daringfireball.markdown"])
        let tags = try #require(alias["UTTypeTagSpecification"] as? [String: Any])
        let aliasExtensions = Set((tags["public.filename-extension"] as? [String]) ?? [])
        #expect(aliasExtensions == ["mdown", "mkd", "mkdn"])
        let declaredExtensions = Set((markdown["CFBundleTypeExtensions"] as? [String]) ?? [])
        #expect(declaredExtensions == aliasExtensions.union(["md", "markdown"]))
    }
}
