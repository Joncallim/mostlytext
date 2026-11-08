import AppKit
import Darwin
import Foundation
import XCTest

/// A fourth, private Finder case. Exact process observations come from the
/// independent unsandboxed host observer; this UI runner records Finder state.
@MainActor
final class ZXPCFinderHoldTests: XCTestCase {
    private let root = "/Users/runner/work/_temp/mostlytext-qljsc"

    func testZFixedHoldSelfRetiresAfterProviderInvalidation() throws {
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
        let marker = finder.staticTexts["MOSTLYTEXT_QL_XPC_HOLD_READY"].firstMatch
        var samples = [[String: Any]]()
        var invalidated: HoldEvidence?
        var markerVisible = false
        let monitoringLimit = ProcessInfo.processInfo.systemUptime + 8
        repeat {
            let previousCheck = samples.last?["check_uptime"] as? Double ?? ready.ready
            let sample = try nextHostSample(for: ready, after: previousCheck)
            let window = finder.windows["Quick Look"].exists
            let markerFound = marker.exists
            let checkedAt = ProcessInfo.processInfo.systemUptime
            markerVisible = markerVisible || (markerFound && checkedAt - start <= 15)
            samples.append(["host_sample_index": sample.index, "uptime": sample.uptime,
                            "host_check_uptime": sample.checkUptime, "check_uptime": checkedAt,
                            "service": sample.service, "provider": sample.provider, "window": window])
            if invalidated == nil {
                invalidated = try? currentEvidence(after: start, invalidationRequired: true)
            }
            if let invalidated, sample.uptime >= invalidated.invalidated + 3 { break }
            if samples.count >= 64 || sample.uptime >= monitoringLimit { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        } while true
        if !markerVisible {
            markerVisible = marker.waitForExistence(timeout: max(0, 15 - (ProcessInfo.processInfo.systemUptime - start)))
                && ProcessInfo.processInfo.systemUptime - start <= 15
        }
        let windowRemained = finder.windows["Quick Look"].exists
        let observedInvalidation = invalidated?.invalidated
        let deadline = observedInvalidation.map { $0 + 3 }
        let allHostSamples = try hostSamples(for: ready)
        let firstAbsent = allHostSamples.first { $0.service == "absent" }
        let serviceDepartedByDeadline = deadline.map { limit in
            firstAbsent.map { $0.uptime >= (observedInvalidation ?? 0) && $0.checkUptime <= limit } == true
                && (allHostSamples.last?.uptime ?? 0) >= limit
                && allHostSamples.last?.service == "absent"
                && allHostSamples.drop { $0.service != "absent" }.allSatisfy { $0.service == "absent" }
        } ?? false
        let providerRemained = allHostSamples.allSatisfy { $0.provider == "expected" }
        let serviceIdentityValid = allHostSamples.first?.service == "expected"
            && allHostSamples.allSatisfy { ["expected", "absent"].contains($0.service) }
        let firstWindowBeforeInvalidation = invalidated.flatMap { lifecycle in
            samples.firstIndex {
                $0["window"] as? Bool == true && $0["service"] as? String == "expected"
                    && ($0["check_uptime"] as? Double ?? .infinity) >= lifecycle.holdStarted
                    && ($0["check_uptime"] as? Double ?? .infinity) < lifecycle.invalidated
            }
        }
        let windowStayedOpen = firstWindowBeforeInvalidation.map { index in
            samples[index...].allSatisfy { $0["window"] as? Bool == true }
        } == true && windowRemained
            && zip(samples, samples.dropFirst()).allSatisfy { earlier, later in
                (later["check_uptime"] as? Double ?? .infinity)
                    - (earlier["check_uptime"] as? Double ?? 0) <= 1.0
            }
        let record: [String: Any] = [
            "kind": "mostlytext-qlxpc-hold-lifecycle", "request_id": ready.id,
            "provider_pid": ready.provider, "service_pid": ready.service,
            "started_uptime": ready.started,
            "hold_started_uptime": invalidated.map { $0.holdStarted } as Any? ?? NSNull(),
            "ready_uptime": ready.ready,
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
            XCTAssertGreaterThanOrEqual(invalidated.invalidated - ready.ready, 1.8)
            XCTAssertLessThanOrEqual(invalidated.invalidated - ready.ready, 2.5)
            XCTAssertLessThan(invalidated.holdStarted, invalidated.invalidated,
                              "The service must enter its non-cooperative hold path before invalidation")
        }
        XCTAssertTrue(serviceIdentityValid, "Observer must see only the exact service PID and executable")
        XCTAssertTrue(providerRemained, "The same provider process must remain alive throughout monitoring")
        XCTAssertTrue(windowStayedOpen, "Finder must be open before invalidation and survive through monitoring")
        XCTAssertTrue(serviceDepartedByDeadline, "The service watchdog must retire the exact held PID within 3 seconds")
    }

    private struct HoldEvidence {
        let id: Int
        let provider: Int32
        let service: Int32
        let started: Double
        let holdStarted: Double
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
              let ready = Double(admitted[0][3]), ready >= begun
        else { throw NSError(domain: "MostlyTextXPCHold", code: 4) }
        let serviceReadyCount = messages.filter { $0 == "QL_XPC_HOLD service-ready id=\(request) pid=\(service) sandbox=1" }.count
        if invalidationRequired && serviceReadyCount != 1 {
            throw NSError(domain: "MostlyTextXPCHold", code: 10)
        }
        let holdStarts = messages.compactMap { fields($0, #"^QL_XPC_HOLD service-hold-start id=(\d+) pid=(\d+) at=([0-9.]+)$"#) }
        if invalidationRequired && holdStarts.count != 1 {
            throw NSError(domain: "MostlyTextXPCHold", code: 9)
        }
        let holdStarted = holdStarts.first.flatMap { row -> Double? in
            guard holdStarts.count == 1, Int(row[0]) == request, Int32(row[1]) == service,
                  let at = Double(row[2]), at >= begun else { return nil }
            return at
        }
        if invalidationRequired && holdStarted == nil {
            throw NSError(domain: "MostlyTextXPCHold", code: 9)
        }
        let invalidations = messages.compactMap { fields($0, #"^QL_XPC_HOLD invalidated id=(\d+) provider=(\d+) service=(\d+) at=([0-9.]+)$"#) }
        if invalidationRequired && invalidations.count != 1 { throw NSError(domain: "MostlyTextXPCHold", code: 5) }
        if invalidationRequired, let row = invalidations.first,
           (invalidations.count != 1 || Int(row[0]) != request || Int32(row[1]) != provider
            || Int32(row[2]) != service
            || Double(row[3]).map({ $0 < ready || $0 <= (holdStarted ?? .infinity) }) != false) {
            throw NSError(domain: "MostlyTextXPCHold", code: 6)
        }
        let evidence = HoldEvidence(id: request, provider: provider, service: service, started: begun,
                                    holdStarted: holdStarted ?? 0, ready: ready,
                                    invalidated: invalidations.first.flatMap { Double($0[3]) } ?? 0)
        try requireWatchdogArm(messages, against: evidence, required: invalidationRequired)
        return evidence
    }

    private func requireWatchdogArm(_ messages: [String], against evidence: HoldEvidence, required: Bool) throws {
        guard required else { return }
        let arms = messages.compactMap {
            fields($0, #"^QL_XPC_HOLD service-watchdog-armed id=(\d+) pid=(\d+) at=([0-9.]+) deadline=([0-9.]+)$"#)
        }
        guard arms.count == 1, Int(arms[0][0]) == evidence.id, Int32(arms[0][1]) == evidence.service,
              let armedAt = Double(arms[0][2]), let deadline = Double(arms[0][3]),
              armedAt >= evidence.started, armedAt <= evidence.ready, armedAt <= evidence.holdStarted,
              (3.9...4.1).contains(deadline - armedAt)
        else { throw NSError(domain: "MostlyTextXPCHold", code: 11) }
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

    private struct HostSample {
        let index: Int
        let uptime: Double
        let checkUptime: Double
        let service: String
        let provider: String
    }

    private func hostSamples(for ready: HoldEvidence) throws -> [HostSample] {
        let url = URL(fileURLWithPath: root + "/hold-process-observer.json")
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 128 * 1024,
              let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              value["kind"] as? String == "mostlytext-qlxpc-host-process",
              value["request_id"] as? Int == ready.id,
              value["provider_pid"] as? Int == Int(ready.provider),
              value["service_pid"] as? Int == Int(ready.service),
              let rows = value["samples"] as? [[String: Any]], !rows.isEmpty, rows.count <= 96
        else { throw NSError(domain: "MostlyTextXPCHold", code: 7) }
        return try rows.enumerated().map { index, row in
            guard row["index"] as? Int == index,
                  let uptime = row["uptime"] as? Double,
                  let checkUptime = row["check_uptime"] as? Double,
                  let service = row["service"] as? String,
                  let provider = row["provider"] as? String,
                  ["expected", "absent", "wrong"].contains(service),
                  ["expected", "absent", "wrong"].contains(provider),
                  checkUptime >= uptime else { throw NSError(domain: "MostlyTextXPCHold", code: 8) }
            return HostSample(index: index, uptime: uptime, checkUptime: checkUptime,
                              service: service, provider: provider)
        }
    }

    private func nextHostSample(for ready: HoldEvidence, after priorCheck: Double) throws -> HostSample {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let sample = try? hostSamples(for: ready).last,
               sample.uptime > priorCheck,
               ProcessInfo.processInfo.systemUptime - sample.checkUptime <= 0.25 {
                return sample
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
        }
        throw NSError(domain: "MostlyTextXPCHold", code: 9)
    }
}
