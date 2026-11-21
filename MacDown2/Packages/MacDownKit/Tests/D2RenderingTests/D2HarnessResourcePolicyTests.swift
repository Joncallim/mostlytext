import DiagramWebKitPool
import Foundation
import Testing

@MainActor
struct D2HarnessResourcePolicyTests {
    @Test(.timeLimit(.minutes(1)))
    func exactBundledWASMIsReadableWithoutOpeningRemoteOrOtherFiles() async throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = package.appendingPathComponent("Sources/D2Rendering/Resources", isDirectory: true)
        let bundle = try #require(Bundle(url: resources))
        let page = try await DiagramHarnessPage.make(
            harnessResourceName: "harness", bundle: bundle,
            bundledSchemeResourceNames: ["harness.html", "d2-browser.js", "render.js", "d2.wasm"]
        )
        defer { page.teardown() }

        let result = try await page.evaluate(
            """
            let wasm;
            try { wasm = new Uint8Array(await (await fetch('./d2.wasm')).arrayBuffer()); }
            catch (error) { return {ok: false, message: 'bundled WASM fetch: ' + error}; }
            if (wasm.length !== 23704068 || wasm[0] !== 0 || wasm[1] !== 97 ||
                wasm[2] !== 115 || wasm[3] !== 109) {
              return {ok: false, message: 'bundled WASM identity differs'};
            }
            for (const url of ['./other.wasm', 'file:///etc/passwd']) {
              try {
                const response = await fetch(url);
                if (response.status !== 0 || (await response.arrayBuffer()).byteLength > 0) {
                  return {ok: false, message: 'unlisted resource was readable: ' + url};
                }
              } catch (_) { /* Denial is expected. */ }
            }
            return await new Promise(resolve => {
              const timer = setTimeout(() => resolve({ok: false, message: 'remote CSP did not report'}), 1500);
              document.addEventListener('securitypolicyviolation', event => {
                if (event.blockedURI.startsWith('http://127.0.0.1:9') &&
                    event.violatedDirective === 'connect-src') {
                  clearTimeout(timer); resolve({ok: true});
                }
              });
              fetch('http://127.0.0.1:9/mostlytext-d2-remote').catch(() => {});
            });
            """,
            arguments: [:]
        )
        if !result.succeeded {
            Issue.record("D2 resource policy failed: \(result.message ?? "no detail")")
        }
    }
}
