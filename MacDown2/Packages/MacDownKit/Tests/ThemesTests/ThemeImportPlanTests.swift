import Foundation
import Testing
@testable import Themes

struct ThemeImportPlanTests {
    @Test func unrelatedImportGetsManagedIdentityInsteadOfExternalAuthority() throws {
        let incoming = try ThemeFile(theme: BundledThemes.light)
        let catalog = try ThemeCatalogSnapshot(revision: 0, customThemes: [])
        let plan = try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        #expect(plan.situation == .newTheme)
        guard case let .install(result) = try plan.resolve(.install, against: catalog) else {
            Issue.record("Expected an installation"); return
        }
        #expect(result.stableID != incoming.stableID)
        #expect(result.hasSameContent(as: incoming))
        #expect(throws: ThemeCatalogError.invalidImportChoice) { try plan.resolve(.replace, against: catalog) }
        #expect(throws: ThemeCatalogError.invalidImportChoice) { try plan.resolve(.useExisting, against: catalog) }
    }

    @Test func reimportOfSameContentIsNoOpEvenAfterManagedIDAssignment() throws {
        let incoming = try ThemeFile(theme: BundledThemes.dark)
        let managed = try ThemeFile(theme: incoming.theme)
        let catalog = try ThemeCatalogSnapshot(revision: 5, customThemes: [managed])
        let plan = try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        #expect(plan.situation == .alreadyInstalled(id: managed.stableID))
        #expect(try plan.resolve(.useExisting, against: catalog) == .unchanged(id: managed.stableID))
        #expect(throws: ThemeCatalogError.invalidImportChoice) { try plan.resolve(.replace, against: catalog) }
        #expect(throws: ThemeCatalogError.invalidImportChoice) { try plan.resolve(.install, against: catalog) }
        guard case let .install(copy) = try plan.resolve(.importCopy, against: catalog) else {
            Issue.record("Expected an explicit copy"); return
        }
        #expect(copy.stableID != incoming.stableID && copy.stableID != managed.stableID)
    }

    @Test func replacementRequiresExplicitChoiceAndRetainsManagedIdentity() throws {
        let existing = try ThemeFile(theme: BundledThemes.light)
        let incoming = try ThemeFile(theme: BundledThemes.dark, stableID: existing.stableID)
        let catalog = try ThemeCatalogSnapshot(revision: 3, customThemes: [existing])
        let plan = try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        #expect(try plan.situation == .conflictingIdentity(
            id: existing.stableID, beforeCanonicalDigest: existing.canonicalDigest()
        ))
        #expect(throws: ThemeCatalogError.invalidImportChoice) { try plan.resolve(.install, against: catalog) }
        guard case let .replace(replacement, digest) = try plan.resolve(.replace, against: catalog) else {
            Issue.record("Expected explicit replacement"); return
        }
        #expect(replacement.stableID == existing.stableID)
        #expect(replacement.hasSameContent(as: incoming))
        #expect(try digest == existing.canonicalDigest())
        guard case let .install(copy) = try plan.resolve(.importCopy, against: catalog) else {
            Issue.record("Expected conflict copy"); return
        }
        #expect(copy.stableID != existing.stableID)
    }

    @Test func recognizedIdentityTakesPrecedenceOverAnotherContentMatch() throws {
        let existing = try ThemeFile(theme: BundledThemes.light)
        let other = try ThemeFile(theme: BundledThemes.dark)
        let incoming = try ThemeFile(theme: other.theme, stableID: existing.stableID)
        let catalog = try ThemeCatalogSnapshot(revision: 1, customThemes: [existing, other])
        let plan = try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        guard case let .conflictingIdentity(id, _) = plan.situation else {
            Issue.record("Expected identity conflict"); return
        }
        #expect(id == existing.stableID)
    }

    @Test func changedRevisionOrBeforeContentInvalidatesAStaleDialog() throws {
        let existing = try ThemeFile(theme: BundledThemes.light)
        let incoming = try ThemeFile(theme: BundledThemes.dark, stableID: existing.stableID)
        let catalog = try ThemeCatalogSnapshot(revision: 8, customThemes: [existing])
        let plan = try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        let newer = try ThemeCatalogSnapshot(revision: 9, customThemes: [existing])
        #expect(throws: ThemeCatalogError.staleImportPlan) { try plan.resolve(.replace, against: newer) }
        let changed = try ThemeCatalogSnapshot(revision: 8, customThemes: [incoming])
        #expect(throws: ThemeCatalogError.staleImportPlan) { try plan.resolve(.replace, against: changed) }
        let deleted = try ThemeCatalogSnapshot(revision: 8, customThemes: [])
        #expect(throws: ThemeCatalogError.staleImportPlan) { try plan.resolve(.replace, against: deleted) }
    }

    @Test func noOpAndCopyAlsoRespectFreshCatalogs() throws {
        let existing = try ThemeFile(theme: BundledThemes.dark)
        let catalog = try ThemeCatalogSnapshot(revision: 1, customThemes: [existing])
        let plan = try ThemeImportPlan(data: existing.encoded(), catalog: catalog)
        let deleted = try ThemeCatalogSnapshot(revision: 1, customThemes: [])
        #expect(throws: ThemeCatalogError.staleImportPlan) { try plan.resolve(.useExisting, against: deleted) }
        let newer = try ThemeCatalogSnapshot(revision: 2, customThemes: [existing])
        #expect(throws: ThemeCatalogError.staleImportPlan) { try plan.resolve(.importCopy, against: newer) }
    }

    @Test func fullCatalogAllowsNoOpAndReplaceButRejectsCopiesAndNewImports() throws {
        let entries = try (0 ..< 256).map { index in
            var theme = BundledThemes.light
            theme.name = "Theme \(index)"
            return try ThemeFile(theme: theme)
        }
        let catalog = try ThemeCatalogSnapshot(revision: 4, customThemes: entries)
        let existing = try #require(entries.first)
        let noOp = try ThemeImportPlan(data: existing.encoded(), catalog: catalog)
        #expect(try noOp.resolve(.useExisting, against: catalog) == .unchanged(id: existing.stableID))
        #expect(throws: ThemeCatalogError.catalogFull) { try noOp.resolve(.importCopy, against: catalog) }
        let incoming = try ThemeFile(theme: BundledThemes.dark)
        #expect(throws: ThemeCatalogError.catalogFull) {
            try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        }
        let replacement = try ThemeFile(theme: incoming.theme, stableID: existing.stableID)
        let plan = try ThemeImportPlan(data: replacement.encoded(), catalog: catalog)
        guard case .replace = try plan.resolve(.replace, against: catalog) else {
            Issue.record("A full catalog must permit replacement"); return
        }
    }

    @Test func catalogRejectsDuplicateIDsAndCountOverflow() throws {
        let entry = try ThemeFile(theme: BundledThemes.light)
        #expect(throws: ThemeCatalogError.duplicateIdentity) {
            try ThemeCatalogSnapshot(revision: 1, customThemes: [entry, entry])
        }
        #expect(throws: ThemeCatalogError.catalogFull) {
            try ThemeCatalogSnapshot(revision: 1, customThemes: Array(repeating: entry, count: 257))
        }
    }

    @Test func generatedIdentityCannotCollideWithSourceOrCatalog() throws {
        let existing = try ThemeFile(theme: BundledThemes.light)
        let incoming = try ThemeFile(theme: BundledThemes.dark)
        let catalog = try ThemeCatalogSnapshot(revision: 1, customThemes: [existing])
        let plan = try ThemeImportPlan(data: incoming.encoded(), catalog: catalog)
        for id in [existing.stableID, incoming.stableID] {
            #expect(throws: ThemeCatalogError.generatedIdentityCollision) {
                try plan.resolve(.install, against: catalog, generatedID: id)
            }
        }
    }

    @Test func restartEquivalentCatalogHasStableDigestAndOrder() throws {
        let first = try ThemeFile(theme: BundledThemes.light)
        let second = try ThemeFile(theme: BundledThemes.dark)
        let restored = try [first, second].map { try ThemeFile.decode($0.encoded()) }
        let original = try ThemeCatalogSnapshot(revision: 7, customThemes: [second, first])
        let restart = try ThemeCatalogSnapshot(revision: 7, customThemes: restored)
        #expect(original == restart)
        #expect(try original.customThemes.map { try $0.canonicalDigest() } == restart.customThemes
            .map { try $0.canonicalDigest() })
        #expect(original.available.count == BundledThemes.all.count + 2)
        #expect(try ThemeCatalogSnapshot(revision: 0, customThemes: []).available == BundledThemes.all)
    }
}
