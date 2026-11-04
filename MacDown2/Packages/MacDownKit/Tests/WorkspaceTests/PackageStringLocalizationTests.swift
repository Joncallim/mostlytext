import Foundation
import Testing
@testable import Workspace

/// Review pass 1: package code called `String(localized:)` without `bundle: .module`, so
/// it resolved against the app's main bundle — which holds none of the package keys — and
/// the fr/pl/ja translations shipped in each package's catalog were unreachable.
struct PackageStringLocalizationTests {
    /// Every package that ships a string catalog must look its strings up in that
    /// catalog's bundle, including FileCore's encoding/status diagnostics.
    @Test func noPackageSourceLooksUpALocalisedStringInTheMainBundle() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var offenders: [String] = []
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            var searchRange = text.startIndex ..< text.endIndex
            while let hit = text.range(of: "String(localized:", range: searchRange) {
                // The call may span lines; look at its text up to the next blank line.
                let tail = text[hit.upperBound...].prefix(600)
                let callText = tail.components(separatedBy: "\n\n").first ?? ""
                if !callText.contains("bundle:") {
                    offenders.append(url.lastPathComponent)
                }
                searchRange = hit.upperBound ..< text.endIndex
            }
        }
        #expect(offenders.isEmpty, "String(localized:) without bundle: .module in \(Set(offenders).sorted())")
    }
}
