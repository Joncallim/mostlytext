import AppKit
import Foundation
@testable import MacDown2
import Testing

@Suite("Bundled license surface")
@MainActor
struct LicenseNoticesTests {
    @Test func bundledTextsMatchTheCanonicalTrackedFilesExactly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let license = try Data(contentsOf: #require(Bundle.main.url(forResource: "LICENSE", withExtension: nil)))
        let notices = try Data(contentsOf: #require(
            Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
        ))
        #expect(try license == Data(contentsOf: root.appendingPathComponent("LICENSE")))
        #expect(try notices ==
            Data(contentsOf: root.appendingPathComponent("compliance/generated/THIRD_PARTY_NOTICES.md")))
        let content = try LicenseNoticesContent.load()
        #expect(Data(content.productLicense.utf8) == license)
        #expect(Data(content.thirdPartyNotices.utf8) == notices)
    }

    @Test func loaderPreservesOriginalUnicodeAndLineEndings() throws {
        let original = "Copyright © Example\r\nOriginal text.\nNo final newline"
        let data = Data(original.utf8)
        let content = try LicenseNoticesContent(product: data, notices: data)
        #expect(Data(content.productLicense.utf8) == data)
        #expect(Data(content.thirdPartyNotices.utf8) == data)
    }

    @Test func emptyInvalidAndOversizedNoticesFailInsteadOfTruncating() {
        let valid = Data("License".utf8)
        #expect(throws: LicenseNoticesContent.Failure.invalidText) {
            try LicenseNoticesContent(product: valid, notices: Data())
        }
        #expect(throws: LicenseNoticesContent.Failure.invalidText) {
            try LicenseNoticesContent(product: Data([255]), notices: valid)
        }
        #expect(throws: LicenseNoticesContent.Failure.oversizedResource) {
            try LicenseNoticesContent(product: valid,
                                      notices: Data(
                                          repeating: 65,
                                          count: LicenseNoticesContent.maximumResourceBytes + 1
                                      ))
        }
    }

    @Test func missingBundledResourceIsAnExplicitFailure() throws {
        try withBundle { bundle in
            #expect(throws: LicenseNoticesContent.Failure.missingResource) {
                try LicenseNoticesContent.load(bundle: bundle)
            }
        }
    }

    @Test func chunkedBundleReadDoesNotTruncateTheNotice() throws {
        let data = Data(String(repeating: "Copyright © Example\n", count: 8000).utf8)
        try withBundle(product: Data("MIT license".utf8), notices: data) { bundle in
            let content = try LicenseNoticesContent.load(bundle: bundle)
            #expect(Data(content.thirdPartyNotices.utf8) == data)
        }
    }

    @Test func oversizedBundleReadFailsRatherThanDisplayingTheAllowedPrefix() throws {
        let data = Data(repeating: 65, count: LicenseNoticesContent.maximumResourceBytes + 1)
        try withBundle(product: Data("MIT license".utf8), notices: data) { bundle in
            #expect(throws: LicenseNoticesContent.Failure.oversizedResource) {
                try LicenseNoticesContent.load(bundle: bundle)
            }
        }
    }

    private func withBundle(
        product: Data? = nil,
        notices: Data? = nil,
        _ operation: (Bundle) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("Empty.bundle")
        let contents = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "test.licenses.\(UUID().uuidString)",
                "CFBundlePackageType": "BNDL",
            ],
            format: .xml, options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try product?.write(to: resources.appendingPathComponent("LICENSE"))
        try notices?.write(to: resources.appendingPathComponent("THIRD_PARTY_NOTICES.md"))
        let bundle = try #require(Bundle(url: bundleURL))
        try operation(bundle)
    }

    @Test func nativeTextIsSelectableReadOnlyAndNeverActivatesLinksOrMarkup() throws {
        let text = "<script>ignored()</script> https://example.invalid\nOriginal license text"
        let scroll = LicenseTextView.makeScrollView(text: text, label: "License text")
        let view = try #require(scroll.documentView as? NSTextView)
        defer { withExtendedLifetime(scroll) {} }
        #expect(view.string == text)
        #expect(!view.isEditable)
        #expect(view.isSelectable)
        #expect(!view.isRichText)
        #expect(view.usesFindPanel)
        #expect(!view.isAutomaticLinkDetectionEnabled)
        #expect(view.textContainer?.widthTracksTextView == true)
        #expect(view.accessibilityLabel() == "License text")
        #expect(view.accessibilityIdentifier() == "licenses.content")
        let attributes = try #require(view.textStorage).attributes(at: 0, effectiveRange: nil)
        #expect(attributes[.link] == nil)
    }
}
