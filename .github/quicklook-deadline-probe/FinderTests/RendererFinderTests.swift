import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class RendererFinderTests: XCTestCase {
    private struct Event {
        let id: Int
        let uptime: Double
    }

    func testActualRichD2AndFallbackWhileRealRendererAPIIsOutstanding() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let smallStart = try open("mostlytext-ql-d2-small.md", in: finder)
        let rich = finder.staticTexts["MOSTLYTEXT_QL_D2_RICH"].firstMatch.waitForExistence(timeout: 15)
        attach("Actual small D2 Finder result")
        XCTAssertTrue(rich, "The real D2 renderer must produce a rich positive, not a fallback/error")
        let small = try waitFor("callback", after: smallStart, timeout: 5)
        _ = try waitFor("worker-terminal", id: small.id, after: small.uptime, timeout: 5)
        XCTAssertNotNil(try event("selected-rich", id: small.id, after: small.uptime))
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(finder.windows["Quick Look"].waitForNonExistence(timeout: 5))

        let largeStart = try open("mostlytext-ql-d2-large.md", in: finder)
        let fallback = finder.staticTexts["MOSTLYTEXT_QL_D2_FALLBACK"].firstMatch.waitForExistence(timeout: 15)
        let visible = ProcessInfo.processInfo.systemUptime
        attach("Actual fallback while real D2 API is outstanding")
        XCTAssertTrue(fallback, "Require a real visible prepared fallback, not a rich/error/busy reply")
        let large = try waitFor("callback", after: largeStart, timeout: 5)
        XCTAssertNil(try event("worker-terminal", id: large.id, after: large.uptime),
                     "The actual renderer API must still be outstanding when the fallback becomes visible")
        let terminal = try waitFor("worker-terminal", id: large.id, after: large.uptime, timeout: 15)
        XCTAssertGreaterThan(terminal.uptime, visible)
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(finder.windows["Quick Look"].waitForNonExistence(timeout: 5))
        let observation: [String: Any] = [
            "kind": "mostlytext-qldeadline-observation", "small_request_id": small.id,
            "large_request_id": large.id, "fallback_visible": visible,
            "large_worker_terminal": terminal.uptime,
        ]
        let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
        let record = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        record.name = "actual-real-renderer-finder-observation.json"
        record.lifetime = .keepAlways
        add(record)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
    }

    private func open(_ name: String, in finder: XCUIApplication) throws -> Double {
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
        return start
    }

    private func attach(_ name: String) {
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = name + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func messages() throws -> [String] {
        let url = URL(fileURLWithPath: "/Users/runner/work/_temp/mostlytext-qldeadline/provider-observer.json")
        let bytes = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(bytes.count, 128 * 1024)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(record["kind"] as? String, "mostlytext-qldeadline-host-observer")
        return try XCTUnwrap(record["messages"] as? [String])
    }

    private func event(_ phase: String, id: Int? = nil, after start: Double) throws -> Event? {
        let expression =
            try NSRegularExpression(pattern: "^QL_DEADLINE_PROBE " + phase + " id=([0-9]+) uptime=([0-9.]+)$")
        return try messages().compactMap { message -> Event? in
            let text = message as NSString
            guard let match = expression.firstMatch(in: message, range: NSRange(location: 0, length: text.length)),
                  let request = Int(text.substring(with: match.range(at: 1))),
                  let uptime = Double(text.substring(with: match.range(at: 2))), uptime >= start,
                  id == nil || id == request else { return nil }
            return Event(id: request, uptime: uptime)
        }.last
    }

    private func waitFor(_ phase: String, id: Int? = nil, after start: Double, timeout: Double) throws -> Event {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let found = try event(phase, id: id, after: start) {
                return found
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Missing actual real-renderer event: " + phase)
        throw NSError(domain: "MostlyTextQLDeadlineProbe", code: 1)
    }
}
