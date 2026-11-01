import Foundation
import Testing
@testable import Themes

struct ThemeFileTests {
    private let identifier = UUID(uuid: (
        0x75,
        0x27,
        0x5A,
        0xE1,
        0xF0,
        0xDB,
        0x4C,
        0x12,
        0xB3,
        0x9E,
        0x04,
        0xF9,
        0xED,
        0x45,
        0xC4,
        0x45
    ))

    @Test func roundTripPreservesIdentityAndEveryColorAndTrait() throws {
        var theme = BundledThemes.dark
        theme.name = "Custom 日本語"
        theme.tokenStyles["markup.link.special"] = TokenStyle(
            color: ThemeColor(red: 0.3, green: 0.2, blue: 0.9, alpha: 0.7),
            bold: true, italic: true, underline: true
        )
        let file = try ThemeFile(theme: theme, stableID: identifier)
        let bytes = try file.encoded()
        let decoded = try ThemeFile.decode(bytes)
        #expect(decoded == file)
        #expect(decoded.stableID == identifier)
        #expect(decoded.theme.id == identifier.uuidString.lowercased())
        #expect(decoded.theme.name == theme.name)
        #expect(decoded.theme.chrome == theme.chrome)
        #expect(decoded.theme.tokenStyles == theme.tokenStyles)
        #expect(try decoded.encoded() == bytes)
        #expect(!BundledThemes.all.map(\.id).contains(decoded.theme.id))
    }

    @Test func poorContrastIsAcceptedAsAnIntentionalUserChoice() throws {
        var theme = BundledThemes.light
        theme.chrome.foreground = theme.chrome.background
        let file = try ThemeFile(theme: theme)
        #expect(try ThemeFile.decode(file.encoded()) == file)
    }

    @Test func optionalChromeAndTokenTraitsCanBeOmitted() throws {
        var object = try fixture()
        var chrome = try #require(object["chrome"] as? [String: Any])
        chrome.removeValue(forKey: "currentLine")
        chrome.removeValue(forKey: "invisibles")
        object["chrome"] = chrome
        object["tokenStyles"] = ["keyword": ["color": color()]]
        let file = try decode(object)
        #expect(file.chrome.currentLine == nil)
        #expect(file.chrome.invisibles == nil)
        #expect(file.tokenStyles["keyword"]?.bold == false)
    }

    @Test(arguments: ["script", "font", "resourceURL", "id", "futureField"])
    func rejectsUnknownRootFields(field: String) throws {
        var object = try fixture()
        object[field] = "untrusted"
        #expect(throws: ThemeFileError.invalidField("theme")) { try decode(object) }
    }

    @Test func rejectsUnknownNestedFields() throws {
        var object = try fixture()
        var chrome = try #require(object["chrome"] as? [String: Any])
        chrome["futureColor"] = color()
        object["chrome"] = chrome
        #expect(throws: ThemeFileError.invalidField("chrome")) { try decode(object) }
        object = try fixture()
        object["tokenStyles"] = ["keyword": ["color": color(), "fontName": "Other"]]
        #expect(throws: ThemeFileError.invalidField("tokenStyles.keyword")) { try decode(object) }
        object["tokenStyles"] = ["keyword": ["color": ["red": 0, "green": 0, "blue": 0, "alpha": 1, "url": 0]]]
        #expect(throws: ThemeFileError.invalidField("tokenStyles.keyword.color")) { try decode(object) }
    }

    @Test(arguments: ["stableID", "displayName", "appearance", "chrome", "tokenStyles", "schemaVersion"])
    func rejectsMissingRequiredFields(field: String) throws {
        var object = try fixture()
        object.removeValue(forKey: field)
        #expect(throws: ThemeFileError.invalidField("theme")) { try decode(object) }
    }

    @Test(arguments: ["0", "2", "-1", "100000000000000000000000"])
    func rejectsUnsupportedSchemaVersions(version: String) throws {
        let text = try fixtureText().replacingOccurrences(
            of: "\"schemaVersion\":1",
            with: "\"schemaVersion\":" + version
        )
        #expect(throws: ThemeFileError.unsupportedVersion) { try ThemeFile.decode(Data(text.utf8)) }
    }

    @Test(arguments: ["true", "1.5", "null", "\"1\""])
    func rejectsNonIntegerSchemaVersions(version: String) throws {
        let text = try fixtureText().replacingOccurrences(
            of: "\"schemaVersion\":1",
            with: "\"schemaVersion\":" + version
        )
        #expect(throws: ThemeFileError.invalidField("schemaVersion")) { try ThemeFile.decode(Data(text.utf8)) }
    }

    @Test(arguments: ["tomorrow-light", "../escape", "", "75275AE1-F0DB-4C12-B39E-04F9ED45C44Z"])
    func rejectsNonUUIDIdentity(value: String) throws {
        var object = try fixture()
        object["stableID"] = value
        #expect(throws: ThemeFileError.self) { try decode(object) }
    }

    @Test(arguments: ["", " leading", "trailing ", "line\nbreak", "bad\u{0000}name", String(repeating: "a", count: 81)])
    func rejectsInvalidDisplayNames(name: String) throws {
        var theme = BundledThemes.light
        theme.name = name
        #expect(throws: ThemeFileError.invalidField("displayName")) { try ThemeFile(theme: theme) }
    }

    @Test(arguments: [
        "", ".keyword", "keyword.", "keyword..control", "Keyword", "keyword/escape", "日本語",
        String(repeating: "k", count: 97),
    ])
    func rejectsUnsafeCaptureNames(capture: String) throws {
        var object = try fixture()
        object["tokenStyles"] = [capture: ["color": color()]]
        #expect(throws: ThemeFileError.invalidField("tokenStyles.capture")) { try decode(object) }
    }

    @Test(arguments: [-0.1, 1.1, Double.infinity, -.infinity, .nan])
    func rejectsInvalidColorChannels(channel: Double) throws {
        var theme = BundledThemes.dark
        theme.chrome.caret.red = channel
        #expect(throws: ThemeFileError.invalidField("chrome.caret")) { try ThemeFile(theme: theme) }
        theme = BundledThemes.dark
        theme.tokenStyles = ["keyword": TokenStyle(color: ThemeColor(red: 0, green: 0, blue: channel))]
        #expect(throws: ThemeFileError.invalidField("tokenStyles.keyword.color")) { try ThemeFile(theme: theme) }
    }

    @Test func requiresOpaqueCanvasAndValidDecodedChannels() throws {
        var object = try fixture()
        var chrome = try #require(object["chrome"] as? [String: Any])
        chrome["background"] = color(alpha: 0.9)
        object["chrome"] = chrome
        #expect(throws: ThemeFileError.invalidField("chrome.background.alpha")) { try decode(object) }
        chrome["background"] = color()
        chrome["caret"] = ["red": 2, "green": 0, "blue": 0, "alpha": 1]
        object["chrome"] = chrome
        #expect(throws: ThemeFileError.invalidField("chrome.caret")) { try decode(object) }
    }

    @Test(arguments: ["false", "null", "\"red\"", "1e999"])
    func rejectsNonNumericColorChannels(channel: String) throws {
        let text = try fixtureText().replacingOccurrences(of: "\"red\":1", with: "\"red\":" + channel)
        #expect(throws: ThemeFileError.self) { try ThemeFile.decode(Data(text.utf8)) }
    }

    @Test(arguments: ["null", "1", "\"true\""])
    func rejectsNonBooleanTraits(value: String) throws {
        var object = try fixture()
        let raw = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        object["tokenStyles"] = ["keyword": ["color": color(), "bold": raw]]
        #expect(throws: ThemeFileError.invalidField("tokenStyles.keyword.bold")) { try decode(object) }
    }

    @Test func boundsTokenCountBeforeConstructingStyles() throws {
        var theme = BundledThemes.dark
        theme.tokenStyles = Dictionary(uniqueKeysWithValues: (0 ..< 512).map {
            ("t\($0)", TokenStyle(color: ThemeColor(red: 0, green: 0, blue: 0)))
        })
        let file = try ThemeFile(theme: theme)
        #expect(try ThemeFile.decode(file.encoded()).tokenStyles.count == 512)
        theme.tokenStyles["extra"] = TokenStyle(color: ThemeColor(red: 0, green: 0, blue: 0))
        #expect(throws: ThemeFileError.tooManyTokenStyles) { try ThemeFile(theme: theme) }
        var object = try fixture()
        object["tokenStyles"] = Dictionary(uniqueKeysWithValues: (0 ..< 513).map { ("t\($0)", ["color": color()]) })
        #expect(throws: ThemeFileError.tooManyTokenStyles) { try decode(object) }
    }

    @Test func exportAlsoRespectsTheByteCeiling() throws {
        var theme = BundledThemes.dark
        theme.tokenStyles = Dictionary(uniqueKeysWithValues: (0 ..< 512).map {
            (String(repeating: "k", count: 90) + String($0), TokenStyle(color: ThemeColor(red: 0, green: 0, blue: 0)))
        })
        #expect(throws: ThemeFileError.fileTooLarge) { try ThemeFile(theme: theme) }
    }

    @Test func inputByteCeilingIncludesWhitespace() throws {
        var bytes = try ThemeFile(theme: BundledThemes.light, stableID: identifier).encoded()
        bytes.append(Data(repeating: 0x20, count: ThemeFile.maximumFileBytes - bytes.count))
        #expect(try ThemeFile.decode(bytes).stableID == identifier)
        bytes.append(0x20)
        #expect(throws: ThemeFileError.fileTooLarge) { try ThemeFile.decode(bytes) }
    }

    @Test(arguments: [
        "{\"a\":1,\"a\":2}", "{\"a\":1,\"\\u0061\":2}",
        "{\"outer\":{\"a\":1,\"a\":2}}",
    ])
    func detectsDuplicatesBeforeFoundationDiscardsThem(text: String) {
        #expect(throws: ThemeFileError.duplicateKey("a")) { try ThemeFile.decode(Data(text.utf8)) }
    }

    @Test func rejectsExcessiveObjectNesting() {
        let text = String(repeating: "{\"a\":", count: 9) + "1" + String(repeating: "}", count: 9)
        #expect(throws: ThemeFileError.excessiveNesting) { try ThemeFile.decode(Data(text.utf8)) }
    }

    @Test(arguments: [
        "", "[]", "{\"a\":[]}", "{\"a\":}", "{\"a\":1,}", "{}{}", "{\"a\":NaN}",
        "{\"a\":\"bad\\x\"}", "{\"a\":\"unterminated}", "{\"a\":\"line\nbreak\"}",
    ])
    func rejectsMalformedJSON(text: String) {
        #expect(throws: ThemeFileError.self) { try ThemeFile.decode(Data(text.utf8)) }
    }

    @Test func rejectsInvalidUTF8AndFutureAppearance() throws {
        #expect(throws: ThemeFileError.invalidJSON) { try ThemeFile.decode(Data([0x7B, 0xFF, 0x7D])) }
        var object = try fixture()
        object["appearance"] = "adaptive"
        #expect(throws: ThemeFileError.self) { try decode(object) }
    }

    private func fixture() throws -> [String: Any] {
        let data = try ThemeFile(theme: BundledThemes.light, stableID: identifier).encoded()
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureText() throws -> String {
        try #require(String(
            data: ThemeFile(theme: BundledThemes.light, stableID: identifier).encoded(),
            encoding: .utf8
        ))
    }

    private func decode(_ object: [String: Any]) throws -> ThemeFile {
        try ThemeFile.decode(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    private func color(alpha: Double = 1) -> [String: Double] {
        ["red": 0, "green": 0, "blue": 0, "alpha": alpha]
    }
}
