import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class XPCFinderTests: XCTestCase {
    func testActualBundledXPCServiceReachability() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let name = "mostlytext-ql-xpc.md"
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
        let visible = finder.staticTexts["MOSTLYTEXT_QL_XPC_PING_OK"].firstMatch.waitForExistence(timeout: 15)
        attachVisibleState(finder)
        XCTAssertTrue(visible, "The actual Finder provider must reach its bundled XPC service")
        let record = try observation(after: start)
        let attachment = try XCTAttachment(
            data: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "actual-xpc-service-reachability.json"
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
            let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(snapshot["kind"] as? String, "mostlytext-qljsc-host-observer")
            let messages = try XCTUnwrap(snapshot["messages"] as? [String])
            var request: Int?
            var provider: Int?
            var began: Double?
            for message in messages {
                let fields = message.split(separator: " ")
                if fields.count == 5, fields[0] == "QL_XPC_PROBE", fields[1] == "begin",
                   let id = Int(fields[2].dropFirst(3)), let pid = Int(fields[3].dropFirst(9)),
                   let time = Double(fields[4].dropFirst(6)), time >= start {
                    request = id
                    provider = pid
                    began = time
                }
                if fields.count == 5, fields[0] == "QL_XPC_PROBE", fields[1] == "admitted",
                   Int(fields[2].dropFirst(3)) == request,
                   let parent = Int(fields[3].dropFirst(9)), parent == provider,
                   let child = Int(fields[4].dropFirst(8)), child > 0, child != parent,
                   let request, let began {
                    return [
                        "kind": "mostlytext-qlxpc-capability", "request_id": request,
                        "provider_pid": parent, "service_pid": child, "started_uptime": began,
                    ]
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require actual provider/service process records from the own-generation live stream")
        throw NSError(domain: "MostlyTextXPCProbe", code: 1)
    }

    private func attachVisibleState(_ finder: XCUIApplication) {
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual bundled XPC service Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual bundled XPC service in Finder"
        image.lifetime = .keepAlways
        add(image)
    }
}
