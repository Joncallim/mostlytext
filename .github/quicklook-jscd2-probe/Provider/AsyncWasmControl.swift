import CryptoKit
import Darwin
import Foundation
import JavaScriptCore
import OSLog

/// A fixed public asynchronous API control, not a general execution or cancellation boundary.
enum AsyncWasmControl {
    private static let logger = Logger(subsystem: "app.mostlytext.qljscd2probe", category: "provider")
    static let wasmHex = "0061736d010000000105016000017f03020100070a0106616e7377657200000a06010400412a0b"

    static func observe() throws -> [String: Any] {
        let started = ProcessInfo.processInfo.systemUptime
        let thread = pthread_mach_thread_np(pthread_self())
        guard let context = JSContext() else { throw Refusal.noContext }
        context.evaluateScript("""
        globalThis.__asyncAnswer = null;
        globalThis.__asyncError = null;
        WebAssembly.instantiate(Uint8Array.from("\(wasmHex)".match(/../g).map(x => parseInt(x, 16))), {})
          .then(value => { __asyncAnswer = value.instance.exports.answer(); })
          .catch(error => { __asyncError = String(error).slice(0, 256); });
        """)
        guard context.exception == nil else { throw Refusal.exception }
        while context.objectForKeyedSubscript("__asyncAnswer").isNull,
              context.objectForKeyedSubscript("__asyncError").isNull,
              ProcessInfo.processInfo.systemUptime < started + 0.25 {
            context.evaluateScript("void 0")
            Thread.sleep(forTimeInterval: 0.001)
        }
        let blockedFinished = !context.objectForKeyedSubscript("__asyncAnswer").isNull
        let blockedEnd = ProcessInfo.processInfo.systemUptime
        while context.objectForKeyedSubscript("__asyncAnswer").isNull,
              context.objectForKeyedSubscript("__asyncError").isNull,
              ProcessInfo.processInfo.systemUptime < started + 2 {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
        let finished = ProcessInfo.processInfo.systemUptime
        let answer = context.objectForKeyedSubscript("__asyncAnswer").toInt32()
        let sameThread = pthread_mach_thread_np(pthread_self()) == thread
        let bytes = try moduleBytes()
        let row: [String: Any] = [
            "kind": "same-thread-public-async-wasm", "module_bytes": bytes.count,
            "module_sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "old_blocking_poll_completed": blockedFinished, "blocked_elapsed_seconds": blockedEnd - started,
            "pumped_elapsed_seconds": finished - blockedEnd, "answer": answer, "same_thread": sameThread,
            "exception_absent": context.exception == nil,
            "rejection_absent": context.objectForKeyedSubscript("__asyncError").isNull,
            "diagnostic_only": true,
        ]
        let encoded = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        guard encoded.count <= 1536 else { throw Refusal.recordBudget }
        let base64 = encoded.base64EncodedString()
        logger.notice("QL_JSCD2_PROBE async-control-base64=\(base64, privacy: .public)")
        guard sameThread, answer == 42, finished - started <= 2, context.exception == nil,
              context.objectForKeyedSubscript("__asyncError").isNull,
              !context.objectForKeyedSubscript("__asyncAnswer").isNull
        else { throw Refusal.actualResult }
        return row
    }

    private static func moduleBytes() throws -> Data {
        let bytes = try stride(from: 0, to: wasmHex.count, by: 2).map { index throws -> UInt8 in
            let lower = wasmHex.index(wasmHex.startIndex, offsetBy: index)
            guard let byte = UInt8(wasmHex[lower ..< wasmHex.index(lower, offsetBy: 2)], radix: 16) else {
                throw Refusal.moduleBytes
            }
            return byte
        }
        return Data(bytes)
    }

    private enum Refusal: Error { case noContext, exception, recordBudget, actualResult, moduleBytes }
}
