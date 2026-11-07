import AppKit
import CryptoKit
import Darwin
import Foundation
import XCTest

@MainActor
final class JSCD2FinderTests: XCTestCase {
    func testActualExistingD2InNetworkDeniedJavaScriptCore() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let name = "mostlytext-ql-jscd2.md"
        let file = finder.descendants(matching: .any).matching(identifier: name).firstMatch
        let named = finder.staticTexts[name].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists)
        if file.exists {
            file.click()
        } else {
            named.click()
        }
        let start = ProcessInfo.processInfo.systemUptime
        finder.typeKey(.space, modifierFlags: [])
        let base = finder.staticTexts["MOSTLYTEXT_QL_JSCD2_REAL_SVG"].firstMatch.waitForExistence(timeout: 15)
        attachVisibleState(finder)
        XCTAssertTrue(base, "Require actual SVG from unchanged bundled D2 engine")
        let (record, data) = try observation(after: start)
        XCTAssertEqual(record["kind"] as? String, "mostlytext-qljscd2-compatibility")
        XCTAssertTrue((record["svg"] as? String)?.contains("JSC_D2_BETA") == true)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "actual-javascriptcore-d2-compatibility.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(finder.windows["Quick Look"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
    }

    private func observation(after start: Double) throws -> ([String: Any], Data) {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            let url = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-qljscd2/provider-observer.json")
            let bytes = try Data(contentsOf: url)
            XCTAssertLessThanOrEqual(bytes.count, 128 * 1024)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(value["kind"] as? String, "mostlytext-qljscd2-host-observer")
            let messages = try XCTUnwrap(value["messages"] as? [String])
            if let raw = decodedRecord(messages),
               let record = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
               let time = record["started_uptime"] as? Double, time >= start {
                XCTAssertTrue((record["svg"] as? String)?.contains("JSC_D2_ALPHA") == true)
                return (record, raw)
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require actual provider capability metadata, not a simulated JS result")
        throw NSError(domain: "MostlyTextJSCProbe", code: 1)
    }

    private func decodedRecord(_ messages: [String]) -> Data? {
        let rows = messages.filter { $0.hasPrefix("QL_JSCD2_PROBE chunk id=2 ") }
        let terminal = messages.filter { $0.hasPrefix("QL_JSCD2_PROBE result id=2 ") }
        guard !rows.isEmpty, rows.count <= 171, terminal.count == 1 else { return nil }
        var raw = Data()
        for (index, row) in rows.enumerated() {
            let fields = row.split(separator: " ").map(String.init)
            guard fields.count == 6, fields[3] == "index=\(index)", fields[4] == "count=\(rows.count)",
                  fields[5].hasPrefix("base64="),
                  let part = Data(base64Encoded: String(fields[5].dropFirst(7))), !part.isEmpty, part.count <= 384
            else { return nil }
            raw.append(part)
        }
        let hash = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        guard raw.count <= 65536,
              terminal[0] == "QL_JSCD2_PROBE result id=2 bytes=\(raw.count) sha256=\(hash)"
        else { return nil }
        return raw
    }

    private func attachVisibleState(_ finder: XCUIApplication) {
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual D2 JavaScriptCore Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual D2 JavaScriptCore capability in Finder"
        image.lifetime = .keepAlways
        add(image)
    }
}
