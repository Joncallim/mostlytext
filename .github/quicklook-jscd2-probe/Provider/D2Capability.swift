import CryptoKit
import Foundation
import JavaScriptCore
import OSLog
import QuickLookUI
import Security

/// Fixed graph compatibility only. One calling thread owns the entire VM lifetime.
enum D2Capability {
    private static let logger = Logger(subsystem: "app.mostlytext.qljscd2probe", category: "provider")

    static func prepare(requestID: Int) throws -> QLPreviewReply {
        let started = ProcessInfo.processInfo.systemUptime
        guard let context = JSContext() else { throw Failure.invalid("no-context") }
        installBridges(context)
        var transform: [String: String] = [:]
        let capture: @convention(block) (String, String) -> Void = { original, transformed in
            transform = [
                "original_sha256": hash(Data(original.utf8)),
                "transformed_sha256": hash(Data(transformed.utf8)),
            ]
        }
        context.setObject(capture, forKeyedSubscript: "__hostWorkerTransform" as NSString)
        var assets: [String: String] = [:]
        for name in ["host", "d2-browser", "control"] {
            guard let url = Bundle(for: StaticPreview.self).url(forResource: name, withExtension: "js") else {
                throw Failure.invalid("missing-asset-" + name)
            }
            let bytes = try Data(contentsOf: url)
            assets[name] = hash(bytes)
            guard let source = String(data: bytes, encoding: .utf8) else { throw Failure.invalid("asset-encoding") }
            context.evaluateScript(source, withSourceURL: url)
            try requireNoException(context, phase: name)
        }
        let deadline = started + 15
        while context.objectForKeyedSubscript("__d2Result").isNull, ProcessInfo.processInfo.systemUptime < deadline {
            context.evaluateScript("__hostTick()")
            try requireNoException(context, phase: "timer")
            Thread.sleep(forTimeInterval: 0.001)
        }
        guard let result = context.objectForKeyedSubscript("__d2Result").toDictionary() as? [String: Any] else {
            throw Failure.invalid("host-wait-budget")
        }
        guard result["ok"] as? Bool == true, let svg = result["svg"] as? String,
              svg.utf8.count <= 48 * 1024, svg.contains("<svg"), svg.contains("JSC_D2_ALPHA"),
              svg.contains("JSC_D2_BETA"), transform.count == 2,
              let controls = result["controls"] as? [String: Any], controls["timer"] as? Bool == true
        else {
            let bounded = String(describing: result.filter { $0.key != "svg" }).prefix(2048)
            logger.error("QL_JSCD2_PROBE refused=\(bounded, privacy: .public)")
            throw Failure.invalid("actual-D2-result")
        }
        let record: [String: Any] = [
            "kind": "mostlytext-qljscd2-compatibility", "request_id": requestID,
            "started_uptime": started, "observed_uptime": ProcessInfo.processInfo.systemUptime,
            "svg": svg, "svg_bytes": svg.utf8.count, "svg_sha256": hash(Data(svg.utf8)),
            "assets": assets, "worker_transform": transform, "controls": controls,
            "diagnostic_only": true, "qualification_candidate": false,
        ]
        return try reply(record: record, svg: svg, requestID: requestID)
    }

    private static func reply(record: [String: Any], svg: String, requestID: Int) throws -> QLPreviewReply {
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard encoded.count <= 64 * 1024 else {
            throw Failure.invalid("record-budget")
        }
        logRecord(encoded, requestID: requestID)
        let policy = [
            "default-src 'none'", "style-src 'unsafe-inline'", "font-src data:",
            "img-src data:", "base-uri 'none'",
        ].joined(separator: "; ")
        let html = Data("""
        <!doctype html><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        <h1>MOSTLYTEXT_QL_JSCD2_REAL_SVG</h1>\(svg)
        """.utf8)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 480)) { _ in
            logger.notice("QL_JSCD2_PROBE factory id=\(requestID) bytes=\(html.count)")
            return html
        }
        reply.title = "MostlyText existing D2 compatibility probe"
        reply.stringEncoding = .utf8
        return reply
    }

    private static func logRecord(_ bytes: Data, requestID: Int) {
        let count = (bytes.count + 767) / 768
        for index in 0 ..< count {
            let part = bytes.subdata(in: index * 768 ..< min((index + 1) * 768, bytes.count)).base64EncodedString()
            logger.notice(
                "QL_JSCD2_PROBE chunk id=\(requestID) index=\(index) count=\(count) base64=\(part, privacy: .public)"
            )
        }
        let digest = hash(bytes)
        logger.notice("QL_JSCD2_PROBE result id=\(requestID) bytes=\(bytes.count) sha256=\(digest, privacy: .public)")
    }

    private static func decodeUTF8(_ bytes: [UInt8]) -> String {
        var iterator = bytes.makeIterator()
        var decoder = Unicode.UTF8()
        var scalars = String.UnicodeScalarView()
        while true {
            switch decoder.decode(&iterator) {
            case let .scalarValue(value): scalars.append(value)
            case .emptyInput: return String(scalars)
            case .error: scalars.append("\u{FFFD}")
            }
        }
    }

    private static func installBridges(_ context: JSContext) {
        let now: @convention(block) () -> Double = { ProcessInfo.processInfo.systemUptime }
        let encode: @convention(block) (String) -> [NSNumber] = { Array($0.utf8).map { NSNumber(value: $0) } }
        let decode: @convention(block) (NSArray) -> String = { values in
            decodeUTF8(values.compactMap { ($0 as? NSNumber)?.uint8Value })
        }
        let atob: @convention(block) (String) -> String = { text in
            guard let bytes = Data(base64Encoded: text) else { return "" }
            return String(String.UnicodeScalarView(bytes.map { UnicodeScalar($0) }))
        }
        let btoa: @convention(block) (String) -> String = { text in
            guard text.unicodeScalars.allSatisfy({ $0.value <= 255 }) else { return "" }
            return Data(text.unicodeScalars.map { UInt8($0.value) }).base64EncodedString()
        }
        let random: @convention(block) (Int) -> [NSNumber] = { count in
            guard (0 ... 65536).contains(count) else { return [] }
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return [] }
            return bytes.map { NSNumber(value: $0) }
        }
        for (name, value) in [
            ("__hostNow", now as Any), ("__hostEncode", encode as Any), ("__hostDecode", decode as Any),
            ("__hostAtob", atob as Any), ("__hostBtoa", btoa as Any), ("__hostRandom", random as Any),
        ] {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }
    }

    private static func requireNoException(_ context: JSContext, phase: String) throws {
        if let error = context.exception {
            let message = String(error.toString().prefix(512))
            logger
                .error("QL_JSCD2_PROBE exception phase=\(phase, privacy: .public) message=\(message, privacy: .public)")
            throw Failure.invalid(phase)
        }
    }

    private static func hash(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private enum Failure: Error { case invalid(String) }
}
