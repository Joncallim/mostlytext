@testable import FileTree
import Foundation
import Testing

struct FileTreeNamingEdgeCaseTests {
    @Test func aCompressedTarballDuplicatesWithItsWholeExtension() {
        #expect(FileTreeNaming.duplicateName(of: "archive.tar.gz", existing: []) == "archive copy.tar.gz")
        #expect(FileTreeNaming
            .duplicateName(of: "archive.tar.gz", existing: ["archive copy.tar.gz"]) == "archive copy 2.tar.gz")
        #expect(FileTreeNaming.duplicateName(of: "data.tar.XZ", existing: []) == "data copy.tar.XZ")
    }

    @Test func ordinaryNamesDuplicateAsBefore() {
        #expect(FileTreeNaming.duplicateName(of: "notes.md", existing: []) == "notes copy.md")
        #expect(FileTreeNaming.duplicateName(of: "v1.2.notes.md", existing: []) == "v1.2.notes copy.md")
        #expect(FileTreeNaming.duplicateName(of: "backup.gz", existing: []) == "backup copy.gz")
        #expect(FileTreeNaming.duplicateName(of: ".gitignore", existing: []) == ".gitignore copy")
        #expect(FileTreeNaming.duplicateName(of: "README", existing: []) == "README copy")
    }

    @Test func duplicateNameUsesTheSelectedLanguageAndPreservesTheExtension() {
        #expect(FileTreeNaming.duplicateName(of: "notes.md", existing: [], copyWord: "copie") == "notes copie.md")
        #expect(FileTreeNaming.duplicateName(
            of: "archive.tar.gz", existing: ["archive copie.tar.gz"], copyWord: "copie"
        ) == "archive copie 2.tar.gz")
    }

    @Test func dotAndDotDotAreNotValidNames() {
        #expect(FileTreeNaming.validate(".", existing: [], currentName: nil) == .nameReserved("."))
        #expect(FileTreeNaming.validate("..", existing: [], currentName: nil) == .nameReserved(".."))
        #expect(FileTreeNaming.validate("...", existing: [], currentName: nil) == nil)
        #expect(FileTreeNaming.validate(".hidden", existing: [], currentName: nil) == nil)
    }

    @Test func aWhitespaceOnlyNameIsEmpty() {
        #expect(FileTreeNaming.validate("   ", existing: [], currentName: nil) == .nameEmpty)
        #expect(FileTreeNaming.validate("\t\n", existing: [], currentName: nil) == .nameEmpty)
    }

    /// Review pass 7: moving or copying an existing file validated its ON-DISK name as if it were typed, so a legal
    /// name such as `Meeting 10:30.md` failed with "Names cannot contain / or :".
    @Test func anExistingFileNameWithAColonIsAcceptedWhenMovedOrCopied() {
        #expect(FileTreeNaming
            .validate("Meeting 10:30.md", existing: [], currentName: nil) == .nameContainsPathSeparator)
        #expect(FileTreeNaming.validate(
            "Meeting 10:30.md", existing: [], currentName: nil, isExistingFileName: true
        ) == nil)
        #expect(FileTreeNaming.validate(
            "a.md", existing: ["A.md"], currentName: nil, isExistingFileName: true
        ) == .nameExists("a.md"))
    }
}

/// Review pass 8: `name.contains("/")` is false for `"x/\u{301}y.md"` (the slash merges with the mark), so a typed name
/// containing a separator slipped past the check and a rename could move the file into another folder.
struct FileTreeNamingScalarTests {
    @Test func aSeparatorGluedToACombiningMarkIsStillRejected() {
        #expect(FileTreeNaming.validate("x/\u{301}y.md", existing: [], currentName: nil) == .nameContainsPathSeparator)
        #expect(FileTreeNaming.validate("a:\u{200C}b", existing: [], currentName: nil) == .nameContainsPathSeparator)
    }
}
