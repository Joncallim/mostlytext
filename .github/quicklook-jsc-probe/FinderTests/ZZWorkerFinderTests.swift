import AppKit
import Darwin
import Foundation
import XCTest

/// Fifth private control. A separate host log reader and process observer
/// inspect worker identities while Finder keeps the Quick Look request open.
@MainActor
final class ZZWorkerFinderTests: XCTestCase {
    private let root = "/Users/runner/work/_temp/mostlytext-qljsc"

    func testZWorkerTimeoutLeavesConcurrentWorkerAlive() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let name = "mostlytext-ql-worker-pair.md"
        let file = finder.descendants(matching: .any).matching(identifier: name).firstMatch
        let named = finder.staticTexts[name].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists)
        if file.exists { file.click() } else { named.click() }
        let started = ProcessInfo.processInfo.systemUptime
        finder.typeKey(.space, modifierFlags: [])

        var sawNormalAliveAfterHeld = false
        var identitySamples = [[String: Any]]()
        let limit = started + 8
        var events = [String]()
        repeat {
            events = try messages()
            let heldEnd = events.compactMap { fields($0, #"^QL_WORKER_BOUNDARY finished id=(\d+) mode=held service=(\d+) worker=(\d+) result=timedOut at=([0-9.]+)$"#) }
                .compactMap { Double($0[3]) }.filter { $0 >= started }.first
            let normalSpawn = events.compactMap { fields($0, #"^QL_WORKER_BOUNDARY spawned id=(\d+) mode=normal service=(\d+) worker=(\d+) at=([0-9.]+)$"#) }
                .first { Double($0[3]).map { $0 >= started } == true }
            if let heldEnd, let normalSpawn, !sawNormalAliveAfterHeld,
               let snapshot = try hostWorkerObservation() {
                identitySamples = snapshot["samples"] as? [[String: Any]] ?? []
                sawNormalAliveAfterHeld = snapshot["kind"] as? String == "mostlytext-qlxpc-host-worker-process"
                    && snapshot["service_pid"] as? Int == Int(normalSpawn[1])
                    && snapshot["normal_pid"] as? Int == Int(normalSpawn[2])
                    && abs((snapshot["held_end_uptime"] as? Double ?? -1) - heldEnd) < 0.001
                    && identitySamples.contains { sample in
                        (sample["check_uptime"] as? Double ?? -1) >= heldEnd
                            && sample["normal"] as? String == "expected"
                    }
            }
            if events.contains(where: { $0.hasPrefix("QL_WORKER_BOUNDARY pair-finished ")
                && $0.contains(" isolated=true ") }) && sawNormalAliveAfterHeld { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        } while ProcessInfo.processInfo.systemUptime < limit

        let marker = finder.staticTexts["MOSTLYTEXT_QL_WORKER_ISOLATION_OK"].firstMatch
        let visible = marker.waitForExistence(timeout: max(0, 15 - (ProcessInfo.processInfo.systemUptime - started)))
        // Finder's WebKit preview exposes the authored <pre> as a StaticText
        // value, not as its accessibility label (observed in the retained UI tree).
        let sourceText = finder.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "# Hosted Quick Look fixture")
        ).firstMatch
        let sourceValue = sourceText.waitForExistence(timeout: 2) ? sourceText.value as? String : nil
        let sourceVisible = sourceValue?.contains("# Hosted Quick Look fixture") == true
        events = try messages()
        let held = events.compactMap { fields($0, #"^QL_WORKER_BOUNDARY finished id=(\d+) mode=held service=(\d+) worker=(\d+) result=timedOut at=([0-9.]+)$"#) }
            .first { Double($0[3]).map { $0 >= started } == true }
        let normal = events.compactMap { fields($0, #"^QL_WORKER_BOUNDARY finished id=(\d+) mode=normal service=(\d+) worker=(\d+) result=completed at=([0-9.]+)$"#) }
            .first { Double($0[3]).map { $0 >= started } == true }
        let distinct = held != nil && normal != nil && held![1] == normal![1] && held![2] != normal![2]
        let order = held.flatMap { Double($0[3]) }.flatMap { heldTime in
            normal.flatMap { Double($0[3]) }.map { heldTime < $0 }
        } == true
        let record: [String: Any] = [
            "kind": "mostlytext-qlxpc-worker-isolation", "started_uptime": started,
            "marker_visible": visible, "source_visible": sourceVisible,
            "source_value": sourceValue ?? "",
            "normal_alive_after_held_timeout": sawNormalAliveAfterHeld,
            "distinct_workers_same_service": distinct, "normal_finished_after_held": order,
            "held_finished": held ?? [], "normal_finished": normal ?? [],
            "identity_samples": identitySamples,
        ]
        let attachment = try XCTAttachment(data: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
        attachment.name = "actual-xpc-worker-isolation.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual bounded worker Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual bounded worker Finder preview"
        image.lifetime = .keepAlways
        add(image)
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(finder.windows["Quick Look"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)
        XCTAssertTrue(visible, "Finder must show the bounded pair result")
        XCTAssertTrue(sourceVisible, "Preview must preserve the prepared source fallback")
        XCTAssertTrue(sawNormalAliveAfterHeld, "Host must independently see the normal child after held timeout")
        XCTAssertTrue(distinct && order, "Held and normal child identities and deadlines must be independent")
    }

    private func messages() throws -> [String] {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: root + "/provider-observer.json"))
        guard bytes.count <= 128 * 1024,
              let snapshot = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              snapshot["kind"] as? String == "mostlytext-qljsc-host-observer",
              let messages = snapshot["messages"] as? [String]
        else { throw NSError(domain: "MostlyTextWorkerProbe", code: 1) }
        return messages
    }

    private func fields(_ message: String, _ pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              match.range.length == (message as NSString).length else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: message) else { return nil }
            return String(message[range])
        }
    }

    private func hostWorkerObservation() throws -> [String: Any]? {
        let path = root + "/worker-process-observer.json"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        guard bytes.count <= 128 * 1024,
              let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              value["kind"] as? String == "mostlytext-qlxpc-host-worker-process" else {
            throw NSError(domain: "MostlyTextWorkerProbe", code: 2)
        }
        return value
    }
}
