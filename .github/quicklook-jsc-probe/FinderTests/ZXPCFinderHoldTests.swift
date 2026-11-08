import AppKit
import Darwin
import Foundation
import XCTest

/// A fourth, private Finder case. Its process observations come from the
/// independent UI runner, not from the provider or the XPC service.
@MainActor
final class ZXPCFinderHoldTests: XCTestCase {
    private let root = "/Users/runner/work/_temp/mostlytext-qljsc"

    func testZFixedHoldRetiresAfterProviderInvalidation() throws {
        continueAfterFailure = false
        let account = try XCTUnwrap(getpwuid(getuid()))
        XCTAssertEqual(getuid(), 501)
        XCTAssertEqual(getuid(), geteuid())
        XCTAssertEqual(String(cString: account.pointee.pw_name), "runner")
        XCTAssertEqual(String(cString: account.pointee.pw_dir), "/Users/runner")
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let name = "mostlytext-ql-xpc-hold.md"
        let file = finder.descendants(matching: .any).matching(identifier: name).firstMatch
        let named = finder.staticTexts[name].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5) || named.exists)
        if file.exists { file.click() } else { named.click() }
        let start = ProcessInfo.processInfo.systemUptime
        finder.typeKey(.space, modifierFlags: [])
        let ready = try waitForEvidence(after: start, invalidationRequired: false, seconds: 5)
        let servicePath = root + "/build/Build/Products/Release/QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex/Contents/XPCServices/QLReplyProbeXPCService.xpc/Contents/MacOS/QLReplyProbeXPCService"
        let providerPath = root + "/build/Build/Products/Release/QLReplyProbeContainer.app/Contents/PlugIns/QLReplyProbeProvider.appex/Contents/MacOS/QLReplyProbeProvider"
        let marker = finder.staticTexts["MOSTLYTEXT_QL_XPC_HOLD_READY"].firstMatch
        var samples = [[String: Any]]()
        var invalidated: HoldEvidence?
        var markerVisible = false
        let monitoringLimit = ProcessInfo.processInfo.systemUptime + 6
        repeat {
            let service = try processState(pid: ready.service, expectedPath: servicePath)
            let serviceAt = ProcessInfo.processInfo.systemUptime
            let provider = try processState(pid: ready.provider, expectedPath: providerPath)
            let window = finder.windows["Quick Look"].exists
            let markerFound = marker.exists
            let checkedAt = ProcessInfo.processInfo.systemUptime
            markerVisible = markerVisible || (markerFound && checkedAt - start <= 15)
            samples.append(["uptime": serviceAt, "check_uptime": checkedAt,
                            "service": service, "provider": provider, "window": window])
            if invalidated == nil {
                invalidated = try? currentEvidence(after: start, invalidationRequired: true)
            }
            if let invalidated, serviceAt >= invalidated.invalidated + 3 { break }
            if samples.count >= 64 || serviceAt >= monitoringLimit { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while true
        if !markerVisible {
            markerVisible = marker.waitForExistence(timeout: max(0, 15 - (ProcessInfo.processInfo.systemUptime - start)))
                && ProcessInfo.processInfo.systemUptime - start <= 15
        }
        let windowRemained = finder.windows["Quick Look"].exists
        let observedInvalidation = invalidated?.invalidated
        let deadline = observedInvalidation.map { $0 + 3 }
        let firstAbsent = samples.first { $0["service"] as? String == "absent" }?["uptime"] as? Double
        let serviceDepartedByDeadline = deadline.map { limit in
            firstAbsent.map { $0 >= (observedInvalidation ?? 0) && $0 <= limit } == true
                && (samples.last?["uptime"] as? Double ?? 0) >= limit
                && samples.last?["service"] as? String == "absent"
        } ?? false
        let providerRemained = samples.allSatisfy { $0["provider"] as? String == "expected" }
        let serviceIdentityValid = samples.first?["service"] as? String == "expected"
            && samples.allSatisfy { ["expected", "absent"].contains($0["service"] as? String ?? "") }
        let firstWindow = samples.firstIndex { $0["window"] as? Bool == true }
        let windowStayedOpen = firstWindow.map { index in
            samples[index...].allSatisfy { $0["window"] as? Bool == true }
        } == true && windowRemained
        let record: [String: Any] = [
            "kind": "mostlytext-qlxpc-hold-lifecycle", "request_id": ready.id,
            "provider_pid": ready.provider, "service_pid": ready.service,
            "started_uptime": ready.started, "ready_uptime": ready.ready,
            "invalidated_uptime": observedInvalidation as Any? ?? NSNull(),
            "samples": samples, "marker_visible": markerVisible,
            "provider_remained": providerRemained, "window_remained": windowStayedOpen,
            "service_identity_valid": serviceIdentityValid,
            "service_departed_by_deadline": serviceDepartedByDeadline,
        ]
        let attachment = try XCTAttachment(data: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
        attachment.name = "actual-xpc-hold-lifecycle.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: String(finder.debugDescription.prefix(65536)))
        tree.name = "Actual XPC hold Finder accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Actual XPC hold in Finder"
        image.lifetime = .keepAlways
        add(image)
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(finder.windows["Quick Look"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "app.mostlytext.MostlyText").isEmpty)
        XCTAssertTrue(markerVisible, "Finder must show the fixed service ready reply within 15 seconds")
        XCTAssertNotNil(invalidated, "The provider must run its independent invalidation timer")
        if let invalidated {
            XCTAssertGreaterThanOrEqual(invalidated.invalidated - ready.ready, 0.35)
            XCTAssertLessThanOrEqual(invalidated.invalidated - ready.ready, 1.5)
        }
        XCTAssertTrue(serviceIdentityValid, "Observer must see only the exact service PID and executable")
        XCTAssertTrue(providerRemained, "The same provider process must remain alive throughout monitoring")
        XCTAssertTrue(windowStayedOpen, "The Finder Quick Look window must remain open throughout monitoring")
        XCTAssertTrue(serviceDepartedByDeadline, "Invalidation must retire the exact held service PID within 3 seconds")
    }

    private struct HoldEvidence {
        let id: Int
        let provider: Int32
        let service: Int32
        let started: Double
        let ready: Double
        let invalidated: Double
    }

    private func waitForEvidence(after start: Double, invalidationRequired: Bool, seconds: Double) throws -> HoldEvidence {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let value = try? currentEvidence(after: start, invalidationRequired: invalidationRequired) {
                return value
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        XCTFail("Require exact own-generation XPC hold service and provider records")
        throw NSError(domain: "MostlyTextXPCHold", code: 1)
    }

    private func currentEvidence(after start: Double, invalidationRequired: Bool) throws -> HoldEvidence {
        let url = URL(fileURLWithPath: root + "/provider-observer.json")
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 128 * 1024,
              let snapshot = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              snapshot["kind"] as? String == "mostlytext-qljsc-host-observer",
              let messages = snapshot["messages"] as? [String]
        else { throw NSError(domain: "MostlyTextXPCHold", code: 2) }
        let begins = messages.compactMap { fields($0, #"^QL_XPC_HOLD begin id=(\d+) provider=(\d+) start=([0-9.]+)$"#) }
            .filter { Double($0[2]).map { $0 >= start } == true }
        guard begins.count == 1, let request = Int(begins[0][0]), request > 0,
              let provider = Int32(begins[0][1]), let begun = Double(begins[0][2]) else {
            throw NSError(domain: "MostlyTextXPCHold", code: 3)
        }
        let admitted = messages.compactMap { fields($0, #"^QL_XPC_HOLD admitted id=(\d+) provider=(\d+) service=(\d+) ready=([0-9.]+)$"#) }
        guard admitted.count == 1, Int(admitted[0][0]) == request, Int32(admitted[0][1]) == provider,
              let service = Int32(admitted[0][2]), service > 0, service != provider,
              let ready = Double(admitted[0][3]), ready >= begun,
              messages.filter({ $0 == "QL_XPC_HOLD service-ready id=\(request) pid=\(service) sandbox=1" }).count == 1
        else { throw NSError(domain: "MostlyTextXPCHold", code: 4) }
        let invalidations = messages.compactMap { fields($0, #"^QL_XPC_HOLD invalidated id=(\d+) provider=(\d+) service=(\d+) at=([0-9.]+)$"#) }
        if invalidationRequired && invalidations.count != 1 { throw NSError(domain: "MostlyTextXPCHold", code: 5) }
        if let row = invalidations.first,
           (invalidations.count != 1 || Int(row[0]) != request || Int32(row[1]) != provider
            || Int32(row[2]) != service || Double(row[3]).map({ $0 < ready }) != false) {
            throw NSError(domain: "MostlyTextXPCHold", code: 6)
        }
        return HoldEvidence(id: request, provider: provider, service: service, started: begun,
                            ready: ready, invalidated: invalidations.first.flatMap { Double($0[3]) } ?? 0)
    }

    private func fields(_ text: String, _ pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range == NSRange(text.startIndex..., in: text)
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private func processState(pid: Int32, expectedPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "pid=", "-o", "uid=", "-o", "comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + .seconds(1)) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + .seconds(1))
            throw NSError(domain: "MostlyTextXPCHold", code: 8)
        }
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        guard bytes.count <= 2048, let value = String(data: bytes, encoding: .utf8) else {
            throw NSError(domain: "MostlyTextXPCHold", code: 7)
        }
        if process.terminationStatus == 1 && value.isEmpty {
            errno = 0
            guard kill(pid, 0) == -1 && errno == ESRCH else { return "wrong" }
            return "absent"
        }
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard process.terminationStatus == 0, parts.count == 3,
              Int32(parts[0]) == pid, Int(parts[1]) == 501,
              String(parts[2]) == expectedPath
        else { return "wrong" }
        return "expected"
    }
}
