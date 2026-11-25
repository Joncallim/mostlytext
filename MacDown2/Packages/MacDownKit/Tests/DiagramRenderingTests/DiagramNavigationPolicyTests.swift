import DiagramWebKitPool
import Foundation
import Testing

@Suite("Bundled diagram navigation boundary")
struct DiagramNavigationPolicyTests {
    @Test func admitsOnlyRealBundledDescendants() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let resources = temporary.appendingPathComponent("Resources", isDirectory: true)
        let nested = resources.appendingPathComponent("nested", isDirectory: true)
        let sibling = temporary.appendingPathComponent("Resources-extra", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let harness = resources.appendingPathComponent("harness.html")
        let nestedScript = nested.appendingPathComponent("render.js")
        let siblingPage = sibling.appendingPathComponent("outside.html")
        for file in [harness, nestedScript, siblingPage] {
            try Data().write(to: file)
        }

        #expect(DiagramNavigationPolicy.allows(harness, within: resources))
        #expect(DiagramNavigationPolicy.allows(nestedScript, within: resources))
        #expect(!DiagramNavigationPolicy.allows(resources, within: resources))
        #expect(!DiagramNavigationPolicy.allows(siblingPage, within: resources))
        #expect(!DiagramNavigationPolicy.allows(
            URL(fileURLWithPath: resources.path + "/../Resources-extra/outside.html"), within: resources
        ))

        let alias = resources.appendingPathComponent("alias.html")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: siblingPage)
        #expect(!DiagramNavigationPolicy.allows(alias, within: resources))
        let internalAlias = resources.appendingPathComponent("internal.js")
        try FileManager.default.createSymbolicLink(at: internalAlias, withDestinationURL: nestedScript)
        #expect(DiagramNavigationPolicy.allows(internalAlias, within: resources))
        #expect(!DiagramNavigationPolicy.allows(
            URL(string: "file://" + resources.path + "/%2E%2E/Resources-extra/outside.html"),
            within: resources
        ))
        #expect(!DiagramNavigationPolicy.allows(URL(string: "https://example.invalid/render"), within: resources))
        #expect(!DiagramNavigationPolicy.allows(
            URL(string: "file://remote-host" + harness.path), within: resources
        ))
        #expect(!DiagramNavigationPolicy.allows(nil, within: resources))
    }

    @Test func topLevelNavigationCannotOpenAnotherBundledResource() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let harness = temporary.appendingPathComponent("harness.html")
        let script = temporary.appendingPathComponent("render.js")
        let alias = temporary.appendingPathComponent("alias.html")
        try Data().write(to: harness)
        try Data().write(to: script)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: harness)

        #expect(DiagramNavigationPolicy.allowsHarnessNavigation(harness, harnessURL: harness))
        #expect(!DiagramNavigationPolicy.allowsHarnessNavigation(script, harnessURL: harness))
        #expect(!DiagramNavigationPolicy.allowsHarnessNavigation(alias, harnessURL: harness))
        #expect(!DiagramNavigationPolicy.allowsHarnessNavigation(
            URL(string: harness.absoluteString + "?other=1"), harnessURL: harness
        ))
        #expect(!DiagramNavigationPolicy.allowsHarnessNavigation(
            URL(string: "https://example.invalid/render"), harnessURL: harness
        ))
        let schemeHarness = try #require(URL(string: "mostlytext-diagram://bundle/harness.html"))
        #expect(DiagramNavigationPolicy.allowsHarnessNavigation(schemeHarness, harnessURL: schemeHarness))
        #expect(!DiagramNavigationPolicy.allowsHarnessNavigation(
            URL(string: "mostlytext-diagram://bundle/render.js"), harnessURL: schemeHarness
        ))
    }
}
