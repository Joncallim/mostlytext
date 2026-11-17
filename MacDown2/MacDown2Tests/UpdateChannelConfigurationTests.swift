import Foundation
@testable import MacDown2
import Testing

@MainActor
@Suite("Sparkle release configuration")
struct UpdateChannelConfigurationTests {
    @Test func admitsOnlyFrozenSignedFeedConfiguration() {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        let valid: [String: Any] = [
            "SUFeedURL": "https://mostlytext.app/appcast.xml",
            "SUPublicEDKey": key,
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true,
        ]
        #expect(UpdateChannelController.hasReleaseConfiguration(info: valid))

        let invalidValues: [(String, Any)] = [
            ("SUFeedURL", "http://mostlytext.app/appcast.xml"),
            ("SUFeedURL", "https://other.example/appcast.xml"),
            ("SUFeedURL", "https://mostlytext.app/appcast.xml?preview=1"),
            ("SUPublicEDKey", "$(MOSTLYTEXT_UPDATE_PUBLIC_ED_KEY)"),
            ("SUPublicEDKey", Data(repeating: 7, count: 31).base64EncodedString()),
            ("SUVerifyUpdateBeforeExtraction", false),
            ("SURequireSignedFeed", false),
        ]
        for (field, replacement) in invalidValues {
            var changed = valid
            changed[field] = replacement
            #expect(!UpdateChannelController.hasReleaseConfiguration(info: changed))
        }
    }
}
