import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class JSCFinderTests: XCTestCase {
    func testActualNetworkDeniedJavaScriptCoreCapability() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let name = "mostlytext-ql-jsc.md"
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
        let base = finder.staticTexts["MOSTLYTEXT_QL_JSC_BASE_42"].firstMatch.waitForExistence(timeout: 15)
        attachVisibleState(finder)
        XCTAssertTrue(base, "Basic JavaScript must genuinely return42 before capability classification")
        let record = try observation(after: start)
        let status = try XCTUnwrap(record["wasmStatus"] as? String)
        XCTAssertTrue(["available", "unavailable", "error"].contains(status))
        XCTAssertTrue(finder.staticTexts["MOSTLYTEXT_QL_JSC_WASM_" + status.uppercased()].firstMatch.exists)
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "actual-javascriptcore-capability.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(finder.windows["Quick Look"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
    }

    private func observation(after start: Double) throws -> [String: Any] {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            let url = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-qljsc/provider-observer.json")
            let bytes = try Data(contentsOf: url)
            XCTAssertLessThanOrEqual(bytes.count, 128 * 1024)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(value["kind"] as? String, "mostlytext-qljsc-host-observer")
            for message in try XCTUnwrap(value["messages"] as? [String]).reversed() {
                let prefix = "QL_JSC_PROBE result="
                if message.hasPrefix(prefix), let raw = message.dropFirst(prefix.count).data(using: .utf8),
                   let record = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
                   let time = record["started_uptime"] as? Double, time >= start {
                    XCTAssertEqual(record["baseJS"] as? Int, 42)
                    return record
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require actual provider capability metadata, not a simulated JS result")
        throw NSError(domain: "MostlyTextJSCProbe", code: 1)
    }

    private func attachVisibleState(_ finder: XCUIApplication) {
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual JavaScriptCore Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual JavaScriptCore capability in Finder"
        image.lifetime = .keepAlways
        add(image)
    }
}
