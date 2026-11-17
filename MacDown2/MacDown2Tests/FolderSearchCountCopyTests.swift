import Foundation
@testable import MacDown2
import Testing

@Suite("Folder search count copy")
struct FolderSearchCountCopyTests {
    private struct PluralCase {
        let language: String
        let count: Int
        let confirmation: String
        let row: String
    }

    private func resources(_ language: String) throws -> Bundle {
        let url = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        return try #require(Bundle(url: url))
    }

    @Test func englishMessagesResolveBothIndependentCounts() throws {
        let bundle = try resources("en")
        let locale = Locale(identifier: "en")
        #expect(FolderSearchCountCopy.confirmation(matches: 1, files: 2)
            .message(bundle: bundle, locale: locale) == "Replace 1 match in 2 files?")
        #expect(FolderSearchCountCopy.summary(matches: 2, files: 1)
            .message(bundle: bundle, locale: locale) == "Replaced 2 matches in 1 file.")
        #expect(FolderSearchCountCopy.unsearched(files: 1)
            .message(bundle: bundle, locale: locale) == "1 file could not be searched and will not be changed.")
        #expect(FolderSearchCountCopy.skipped(files: 1)
            .message(bundle: bundle, locale: locale) == "and 1 more file not modified")
        #expect(FolderSearchCountCopy.result(path: "100% %@ note.md", matches: 1)
            .message(bundle: bundle, locale: locale) == "Matches in 100% %@ note.md: 1 match")
        #expect(FolderSearchCountCopy.result(path: "user note.md", matches: 0)
            .message(bundle: bundle, locale: locale) == "Matches in user note.md: 0 matches")
    }

    @Test func compiledPluralFamiliesKeepPathAndGrammar() throws {
        let cases: [PluralCase] = [
            .init(language: "fr", count: 0, confirmation: "Remplacer 0 correspondance dans 0 fichier ?",
                  row: "Correspondances dans note.md : 0 correspondance"),
            .init(language: "fr", count: 2, confirmation: "Remplacer 2 correspondances dans 2 fichiers ?",
                  row: "Correspondances dans note.md : 2 correspondances"),
            .init(language: "ja", count: 1, confirmation: "1ファイルの1件の一致を置換しますか？",
                  row: "note.md の一致: 1件"),
            .init(language: "pl", count: 1, confirmation: "Zastąpić 1 dopasowanie w 1 pliku?",
                  row: "Dopasowania w note.md: 1 dopasowanie"),
            .init(language: "pl", count: 2, confirmation: "Zastąpić 2 dopasowania w 2 plikach?",
                  row: "Dopasowania w note.md: 2 dopasowania"),
            .init(language: "pl", count: 5, confirmation: "Zastąpić 5 dopasowań w 5 plikach?",
                  row: "Dopasowania w note.md: 5 dopasowań"),
            .init(language: "pl", count: 22, confirmation: "Zastąpić 22 dopasowania w 22 plikach?",
                  row: "Dopasowania w note.md: 22 dopasowania"),
        ]
        for item in cases {
            let bundle = try resources(item.language)
            let locale = Locale(identifier: item.language)
            #expect(FolderSearchCountCopy.confirmation(matches: item.count, files: item.count)
                .message(bundle: bundle, locale: locale) == item.confirmation)
            #expect(FolderSearchCountCopy.result(path: "note.md", matches: item.count)
                .message(bundle: bundle, locale: locale) == item.row)
        }
    }

    @Test func reorderedJapaneseCopyKeepsIndependentArgumentIdentity() throws {
        let bundle = try resources("ja")
        let locale = Locale(identifier: "ja")
        #expect(FolderSearchCountCopy.confirmation(matches: 1, files: 2)
            .message(bundle: bundle, locale: locale) == "2ファイルの1件の一致を置換しますか？")
    }
}
