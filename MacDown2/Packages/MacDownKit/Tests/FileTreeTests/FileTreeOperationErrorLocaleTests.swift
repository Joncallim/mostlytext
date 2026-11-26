@testable import FileTree
import Foundation
import Testing

@Suite("File Tree operation error locale")
struct FileTreeOperationErrorLocaleTests {
    @Test func deferredDragRefusalFollowsPresentationLanguage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mostlytext-filetree-locale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (language, text) in [("en", "EN_UNTRUSTED_MOVE"), ("fr", "FR_UNTRUSTED_MOVE")] {
            let folder = root.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "\"Untrusted folder move.\" = \"\(text)\";\n".write(
                to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8
            )
        }
        let bundle = try #require(Bundle(url: root))
        let failure = FileTreeOperationError.untrustedMove
        #expect(failure.message(locale: Locale(identifier: "fr"), bundle: bundle) == "FR_UNTRUSTED_MOVE")
        #expect(failure.message(locale: Locale(identifier: "en"), bundle: bundle) == "EN_UNTRUSTED_MOVE")
        #expect(FileTreeOperationError.underlying("authored detail")
            .message(locale: Locale(identifier: "fr"), bundle: bundle) == "authored detail")
    }
}
