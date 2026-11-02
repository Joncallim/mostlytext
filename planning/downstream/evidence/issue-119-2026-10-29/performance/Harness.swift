@testable import FileCore
import Darwin
import Dispatch
import Foundation

// Component measurement only. Calls are serial; this does not exercise or establish admission bounds.
private struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private enum Operation: String, Encodable, Sendable, Equatable {
    case snapshot, revision, probe
}

private struct Configuration: Sendable {
    let operation: Operation
    let url: URL
    let expectedSize: Int
    let expectedHash: String
    let warmCount: Int?

    static func parse(_ arguments: [String]) throws -> Configuration {
        let usage = "Usage: harness snapshot|revision|probe PATH --expected-size BYTES --expected-sha256 HEX (--once | --warm-count 1...200)"
        guard arguments.count >= 3, let operation = Operation(rawValue: arguments[1]) else {
            throw HarnessFailure(description: usage)
        }
        var size: Int?
        var hash: String?
        var warmCount: Int?
        var once = false
        var index = 3
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--once" {
                guard !once, warmCount == nil else { throw HarnessFailure(description: usage) }
                once = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw HarnessFailure(description: usage) }
            let value = arguments[index + 1]
            switch flag {
            case "--expected-size":
                guard size == nil, let parsed = Int(value), (1 ... 33_554_432).contains(parsed) else {
                    throw HarnessFailure(description: "Expected size must be 1...33554432 bytes, specified once")
                }
                size = parsed
            case "--expected-sha256":
                let normalized = value.lowercased()
                guard hash == nil, normalized.utf8.count == 64,
                      normalized.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) })
                else { throw HarnessFailure(description: "Expected SHA-256 must be 64 hexadecimal digits, specified once") }
                hash = normalized
            case "--warm-count":
                guard !once, warmCount == nil, let parsed = Int(value), (1 ... 200).contains(parsed) else {
                    throw HarnessFailure(description: usage)
                }
                warmCount = parsed
            default:
                throw HarnessFailure(description: usage)
            }
            index += 2
        }
        guard let size, let hash, once || warmCount != nil else { throw HarnessFailure(description: usage) }
        return Configuration(
            operation: operation, url: URL(fileURLWithPath: arguments[2]).standardizedFileURL,
            expectedSize: size, expectedHash: hash, warmCount: warmCount
        )
    }
}

private struct MemorySample: Encodable, Sendable {
    // Darwin's ru_maxrss is bytes, unlike Linux's KiB. Peak covers the whole process lifetime.
    let residentBytes: UInt64?
    let physicalFootprintBytes: UInt64?
    let processPeakResidentBytes: Int64?
    let taskInfoStatus: Int32
    let getrusageStatus: Int32

    static func capture() -> MemorySample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var usage = rusage()
        let usageStatus = getrusage(RUSAGE_SELF, &usage)
        return MemorySample(
            residentBytes: status == KERN_SUCCESS ? UInt64(info.resident_size) : nil,
            physicalFootprintBytes: status == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil,
            processPeakResidentBytes: usageStatus == 0 ? Int64(usage.ru_maxrss) : nil,
            taskInfoStatus: status, getrusageStatus: usageStatus
        )
    }
}

private struct ResultSummary: Encodable, Sendable {
    let byteCount: Int
    let sha256: String
    let encodingRawValue: UInt?
    let hasNoBOM: Bool?
    let textIsEmpty: Bool?

    init(_ revision: FileRevision) {
        byteCount = revision.fileSize
        sha256 = revision.sha256
        encodingRawValue = nil
        hasNoBOM = nil
        textIsEmpty = nil
    }

    init(_ snapshot: FileSnapshot) {
        byteCount = snapshot.revision.fileSize
        sha256 = snapshot.revision.sha256
        encodingRawValue = snapshot.encodingRawValue
        hasNoBOM = snapshot.bom == .none
        textIsEmpty = snapshot.text.isEmpty
    }

    func validationError(for configuration: Configuration) -> String? {
        guard byteCount == configuration.expectedSize else { return "File byte count does not match expected size" }
        guard sha256 == configuration.expectedHash else { return "SHA-256 does not match expected fixture digest" }
        if let encodingRawValue {
            guard encodingRawValue == String.Encoding.utf8.rawValue, hasNoBOM == true, textIsEmpty == false else {
                return "Snapshot is not nonempty UTF-8 without a BOM, as required by this harness fixture contract"
            }
        }
        return nil
    }
}

private struct TimedResult: Sendable {
    let apiNanoseconds: UInt64
    let result: ResultSummary?
    let apiError: String?
}

private func measureSynchronous(_ configuration: Configuration) -> TimedResult {
    // Neither the payload nor Foundation autoreleased read objects escape into the sample log/next call.
    autoreleasepool {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            switch configuration.operation {
            case .snapshot:
                let snapshot = try FileStore().readSnapshot(from: configuration.url, decoding: .automatic)
                let end = DispatchTime.now().uptimeNanoseconds
                return TimedResult(apiNanoseconds: end - start, result: ResultSummary(snapshot), apiError: nil)
            case .revision:
                let revision = try FileStore().readRevision(from: configuration.url)
                let end = DispatchTime.now().uptimeNanoseconds
                return TimedResult(apiNanoseconds: end - start, result: ResultSummary(revision), apiError: nil)
            case .probe:
                return TimedResult(apiNanoseconds: 0, result: nil, apiError: "Internal harness dispatch error")
            }
        } catch {
            let end = DispatchTime.now().uptimeNanoseconds
            return TimedResult(apiNanoseconds: end - start, result: nil, apiError: String(describing: error))
        }
    }
}

private func measureProbe(_ configuration: Configuration) async -> TimedResult {
    let start = DispatchTime.now().uptimeNanoseconds
    let observation = await DocumentFileProbe().observe(
        expectedURL: configuration.url, priorFileObjectID: nil, decoding: .automatic
    )
    let end = DispatchTime.now().uptimeNanoseconds
    return autoreleasepool {
        switch observation {
        case let .available(snapshot):
            TimedResult(apiNanoseconds: end - start, result: ResultSummary(snapshot), apiError: nil)
        case .moved:
            TimedResult(apiNanoseconds: end - start, result: nil, apiError: "Probe unexpectedly reported a moved fixture")
        case .missing:
            TimedResult(apiNanoseconds: end - start, result: nil, apiError: "Probe reported a missing fixture")
        case let .unavailable(_, issue):
            TimedResult(apiNanoseconds: end - start, result: nil, apiError: "Probe unavailable: \(issue)")
        }
    }
}

private struct Sample: Encodable {
    let type = "sample"
    let processID: Int32
    let sampleIndex: Int
    let operation: Operation
    let cacheLabel: String
    let apiNanoseconds: UInt64
    let outerDetachedNanoseconds: UInt64
    let result: ResultSummary?
    let validationError: String?
    let memoryBefore: MemorySample
    let memoryAfter: MemorySample
}

private struct RunDescription: Encodable {
    let type = "run"
    let schemaVersion = 1
    let processID = getpid()
    let startedAt = ISO8601DateFormatter().string(from: Date())
    let operation: Operation
    let fixturePath: String
    let expectedSize: Int
    let expectedSHA256: String
    let measuredWarmSamples: Int?
    let totalCalls: Int
    let cachePolicy = "No cache eviction. Fresh process does not establish cold storage; fixture creation may warm filesystem caches."
    let boundary = "Serial FileCore component harness; no native windows, lifecycle, admission-bound or MainActor-I/O proof."
}

private func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var line = try encoder.encode(value)
    line.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: line)
}

@main
private struct Harness {
    static func main() async {
        do {
            let configuration = try Configuration.parse(CommandLine.arguments)
            let callCount = configuration.warmCount.map { $0 + 1 } ?? 1
            try emit(RunDescription(
                operation: configuration.operation, fixturePath: configuration.url.path,
                expectedSize: configuration.expectedSize, expectedSHA256: configuration.expectedHash,
                measuredWarmSamples: configuration.warmCount, totalCalls: callCount
            ))
            for index in 0 ..< callCount {
                let before = MemorySample.capture()
                let start = DispatchTime.now().uptimeNanoseconds
                let timed = await Task.detached(priority: .utility) {
                    if configuration.operation == .probe {
                        return await measureProbe(configuration)
                    }
                    return measureSynchronous(configuration)
                }.value
                let end = DispatchTime.now().uptimeNanoseconds
                let after = MemorySample.capture()
                let validationError = timed.apiError ?? timed.result?.validationError(for: configuration)
                let cacheLabel = configuration.warmCount == nil
                    ? "first-read-fresh-process-cache-uncontrolled"
                    : (index == 0 ? "priming-read-cache-uncontrolled" : "warm-same-process")
                try emit(Sample(
                    processID: getpid(), sampleIndex: index, operation: configuration.operation,
                    cacheLabel: cacheLabel, apiNanoseconds: timed.apiNanoseconds,
                    outerDetachedNanoseconds: end - start, result: timed.result,
                    validationError: validationError, memoryBefore: before, memoryAfter: after
                ))
                if let validationError { throw HarnessFailure(description: validationError) }
                guard timed.result != nil else { throw HarnessFailure(description: "Missing operation result") }
            }
        } catch {
            let message = "Harness failed: \(error)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}
