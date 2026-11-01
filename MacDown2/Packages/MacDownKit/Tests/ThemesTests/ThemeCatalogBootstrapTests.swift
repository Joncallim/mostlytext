import Foundation
import Testing
@testable import Themes

struct ThemeCatalogBootstrapTests {
    @Test func createsPrivateFoldersAndReusesTheSameCatalogWithoutReplacingFiles() async throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let components = ["Application Support", "MacDown 2", "Themes"]
        let store = try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.base, components: components)
        let theme = try ThemeFile(theme: BundledThemes.light)
        let prepared = try await store.prepareImport(theme.encoded())
        let installed = try await store.commitImport(prepared, choice: .install)
        let again = try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.base, components: components)
        #expect(try await again.reload().catalog.customThemes == installed.state.catalog.customThemes)
        var url = fixture.base
        for component in components {
            url.appendPathComponent(component, isDirectory: true)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        }
    }

    @Test func symlinkedChildCannotCreateFoldersOutsideTheGrantedParent() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let target = fixture.base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("alias"),
                                                   withDestinationURL: target)
        #expect(throws: ThemeStorageError.invalidDirectory) {
            try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.root, components: ["alias", "Themes"])
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    @Test func existingNonprivateLeafIsRejectedWithoutChangingItsPermissions() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        let existing = fixture.root.appendingPathComponent("Themes")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755])
        #expect(throws: ThemeStorageError.invalidDirectory) {
            try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.root, components: ["Themes"])
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: existing.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    }

    @Test(arguments: [[], [".."], ["."], ["a/b"], ["bad\u{0000}name"], Array(repeating: "x", count: 9)])
    func invalidComponentsHaveNoSideEffects(components: [String]) throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        #expect(throws: ThemeStorageError.invalidDirectory) {
            try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.root, components: components)
        }
        #expect(try fixture.names().isEmpty)
    }

    @Test func anUntrustedWritableParentIsRejectedBeforeCreation() throws {
        let fixture = try ThemeDirectoryFixture(); defer { fixture.cleanup() }
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: fixture.root.path)
        #expect(throws: ThemeStorageError.invalidDirectory) {
            try ThemeCatalogStore.prepareManagedDirectory(beneath: fixture.root, components: ["Themes"])
        }
        #expect(try fixture.names().isEmpty)
    }
}
