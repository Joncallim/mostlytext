import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class PendingFinderTests: XCTestCase {
    private struct Event {
        let id: Int
        let uptime: Double
    }

    func testActualFinderClosureWhileProviderIsPending() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        var observation: [String: Any] = [
            "kind": "mostlytext-qlcancel-observation",
            "selected": "mostlytext-ql-reply-cancel.md",
        ]
        defer { attach(observation) }
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let fileName = "mostlytext-ql-reply-cancel.md"
        let file = finder.descendants(matching: .any).matching(identifier: fileName).firstMatch
        let named = finder.staticTexts[fileName].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists)
        if file.exists {
            file.click()
        } else {
            named.click()
        }
        let start = ProcessInfo.processInfo.systemUptime
        finder.typeKey(.space, modifierFlags: [])
        let window = finder.windows[fileName].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "The real pending Quick Look window must exist")
        let pending = try waitForEvent("pending", after: start, timeout: 5)
        observation["request_id"] = pending.id
        observation["provider_started"] = pending.uptime
        observation["observed_pending"] = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(try event("terminal-completed", id: pending.id, after: pending.uptime))
        XCTAssertNil(try event("terminal-cancelled", id: pending.id, after: pending.uptime))
        observation["escape_sent"] = ProcessInfo.processInfo.systemUptime
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(window.waitForNonExistence(timeout: 5), "Require actual window disappearance after Escape")
        observation["window_closed"] = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText")
            .isEmpty)
        let terminal = try waitForTerminal(id: pending.id, after: pending.uptime)
        observation["terminal_kind"] = terminal.kind
        observation["provider_terminal"] = terminal.time
        observation["system_task_cancellation_observed"] = terminal.kind == "terminal-cancelled"
    }

    private func waitForTerminal(id: Int, after start: Double) throws -> (kind: String, time: Double) {
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while ProcessInfo.processInfo.systemUptime < deadline {
            for outcome in ["terminal-cancelled", "terminal-completed"] {
                if let terminal = try event(outcome, id: id, after: start) {
                    return (outcome, terminal.uptime)
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require actual system cancellation or actual delayed completion after real Finder closure")
        throw NSError(domain: "MostlyTextQLCancellationProbe", code: 2)
    }

    private func attach(_ observation: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]) {
            let record = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            record.name = "actual-pending-finder-observation.json"
            record.lifetime = .keepAlways
            add(record)
        }
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual pending Finder accessibility state"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual Finder after pending-request observation"
        image.lifetime = .keepAlways
        add(image)
    }

    private func messages() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--last",
            "1m",
            "--style",
            "json",
            "--predicate",
            "subsystem == \"app.mostlytext.qlcancelprobe\"",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Only this fixture's own provider events may be observed")
        XCTAssertLessThanOrEqual(bytes.count, 128 * 1024)
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
        return rows.compactMap { $0["eventMessage"] as? String }
    }

    private func event(_ phase: String, id: Int? = nil, after start: Double) throws -> Event? {
        let expression = try NSRegularExpression(pattern: "QL_CANCEL_PROBE " + phase + " id=([0-9]+) uptime=([0-9.]+)")
        return try messages().compactMap { message -> Event? in
            let text = message as NSString
            guard let match = expression.firstMatch(in: message, range: NSRange(location: 0, length: text.length)),
                  let requestID = Int(text.substring(with: match.range(at: 1))),
                  let uptime = Double(text.substring(with: match.range(at: 2))), uptime >= start,
                  id == nil || id == requestID else { return nil }
            return Event(id: requestID, uptime: uptime)
        }.last
    }

    private func waitForEvent(_ phase: String, after start: Double, timeout: Double) throws -> Event {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let observed = try event(phase, after: start) {
                return observed
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require the actual provider to be pending before sending Escape")
        throw NSError(domain: "MostlyTextQLCancellationProbe", code: 1)
    }
}
