import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class WorkerFinderTests: XCTestCase {
    func testActualInheritedWorkerNormalAndPhysicalDeadline() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let name = "mostlytext-ql-worker.md"
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
        let visible = finder.staticTexts["MOSTLYTEXT_QL_WORKER_NORMAL_OK"].firstMatch.waitForExistence(timeout: 15)
        attachVisibleState(finder)
        XCTAssertTrue(visible, "The actual inherited child must complete inside the Finder provider")
        XCTAssertTrue(finder.staticTexts["MOSTLYTEXT_QL_WORKER_HARD_LIMIT_OK"].firstMatch.exists)
        let record = try observation(after: start)
        let attachment = try XCTAttachment(data: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
        attachment.name = "actual-inherited-worker.json"
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
            if let record = try observedRecord(messages: messages, after: start) {
                return record
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require actual parent/child/deadline records from the admitted own-generation live stream")
        throw NSError(domain: "MostlyTextWorkerProbe", code: 1)
    }

    private func observedRecord(messages: [String], after start: Double) throws -> [String: Any]? {
        var children: [[String: Any]] = []
        var request: Int?
        var parent: Int?
        var began: Double?
        var workerHash: String?
        for message in messages {
            let fields = message.split(separator: " ")
            if fields.count == 5, fields[0] == "QL_WORKER_PROBE", fields[1] == "begin",
               let id = Int(fields[2].dropFirst(3)), let pid = Int(fields[3].dropFirst(7)),
               let time = Double(fields[4].dropFirst(6)), time >= start {
                request = id; parent = pid; began = time
            }
            if fields.count == 4, fields[0] == "QL_WORKER_PROBE", fields[1] == "executable",
               Int(fields[2].dropFirst(3)) == request {
                workerHash = String(fields[3].dropFirst(7))
            }
            let prefix = "QL_WORKER_PROBE child="
            if message.hasPrefix(prefix), let bytes = message.dropFirst(prefix.count).data(using: .utf8),
               let row = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
               row["request_id"] as? Int == request {
                children.append(row)
            }
        }
        guard let request, let parent, let began, let workerHash, children.count == 2 else { return nil }
        XCTAssertEqual(children[0]["mode"] as? String, "normal")
        XCTAssertEqual(children[0]["status"] as? Int, 0)
        XCTAssertEqual(children[1]["mode"] as? String, "held")
        XCTAssertEqual(children[1]["status"] as? Int, Int(SIGKILL))
        XCTAssertNotEqual(children[0]["pid"] as? Int, children[1]["pid"] as? Int)
        return [
            "kind": "mostlytext-qlworker-capability", "request_id": request, "provider_pid": parent,
            "started_uptime": began, "worker_sha256": workerHash, "children": children,
        ]
    }

    private func attachVisibleState(_ finder: XCUIApplication) {
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual inherited worker Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual inherited worker in Finder"
        image.lifetime = .keepAlways
        add(image)
    }
}
