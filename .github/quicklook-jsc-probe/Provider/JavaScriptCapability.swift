import Foundation
import JavaScriptCore
import OSLog
import QuickLookUI

/// Finite compiled-in capability control; no authored source or native bindings enter this VM.
enum JavaScriptCapability {
    static let wasmHex = "0061736d010000000105016000017f03020100070a0106616e7377657200000a06010400412a0b"
    private static let logger = Logger(subsystem: "app.mostlytext.qljscprobe", category: "provider")

    static func prepare(requestID: Int) throws -> QLPreviewReply {
        let started = ProcessInfo.processInfo.systemUptime
        guard let context = JSContext() else { throw ControlError.noContext }
        guard let value = context.evaluateScript(program), context.exception == nil,
              let text = value.toString(), let bytes = text.data(using: .utf8), bytes.count <= 4096,
              var record = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              record["baseJS"] as? Int == 42, record["moduleHex"] as? String == wasmHex,
              let status = record["wasmStatus"] as? String, ["available", "unavailable", "error"].contains(status)
        else { throw ControlError.invalidResult }
        record["kind"] = "mostlytext-qljsc-capability"
        record["request_id"] = requestID
        record["started_uptime"] = started
        record["observed_uptime"] = ProcessInfo.processInfo.systemUptime
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard encoded.count <= 8192, let json = String(data: encoded, encoding: .utf8) else {
            throw ControlError.invalidResult
        }
        logger.notice("QL_JSC_PROBE result=\(json, privacy: .public)")
        let escaped = json.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'">
        <h1>MOSTLYTEXT_QL_JSC_BASE_42</h1>
        <h2>MOSTLYTEXT_QL_JSC_WASM_\(status.uppercased())</h2><pre>\(escaped)</pre>
        """.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            logger.notice("QL_JSC_PROBE factory id=\(requestID) bytes=\(html.count)")
            return html
        }
        reply.title = "MostlyText JavaScriptCore capability probe"
        reply.stringEncoding = .utf8
        return reply
    }

    private static var program: String {
        """
        (() => {
          const hex = "\(wasmHex)";
          const result = {baseJS: 6 * 7, moduleHex: hex, wasmType: typeof WebAssembly,
            workerType: typeof Worker, domType: typeof document, fetchType: typeof fetch,
            objcType: typeof ObjC, wasmStatus: "unavailable", wasmAnswer: null,
            errorPhase: null, errorName: null, errorMessage: null};
          if (typeof WebAssembly !== "undefined") {
            let phase = "module";
            try {
              const bytes = Uint8Array.from(hex.match(/../g).map(value => parseInt(value, 16)));
              const module = new WebAssembly.Module(bytes);
              phase = "instance";
              const instance = new WebAssembly.Instance(module, {});
              phase = "execution";
              result.wasmAnswer = instance.exports.answer();
              result.wasmStatus = result.wasmAnswer === 42 ? "available" : "wrong-answer";
            } catch (error) {
              result.wasmStatus = "error";
              result.errorPhase = phase;
              result.errorName = String(error.name).slice(0, 128);
              result.errorMessage = String(error.message).slice(0, 512);
            }
          }
          return JSON.stringify(result);
        })()
        """
    }

    private enum ControlError: Error { case noContext, invalidResult }
}
