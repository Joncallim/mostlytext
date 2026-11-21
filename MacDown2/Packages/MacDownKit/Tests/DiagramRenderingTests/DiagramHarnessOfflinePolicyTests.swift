@testable import DiagramWebKitPool
import Foundation
import Testing

/// Execute the shipped Mermaid page policy in WebKit. A rejected fetch must
/// report a CSP violation; a dead or unreachable server would not satisfy it.
@MainActor
struct DiagramHarnessOfflinePolicyTests {
    @Test func bundledMermaidHarnessRejectsRemoteFetchAndImage() async throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let package = tests.deletingLastPathComponent().deletingLastPathComponent()
        let resources = package.appendingPathComponent("Sources/DiagramRendering/Resources", isDirectory: true)
        let bundle = try #require(Bundle(url: resources))
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        defer { page.teardown() }

        let result = try await page.evaluate(
            """
            return await new Promise(resolve => {
              const blocked = new Set();
              const timer = setTimeout(() => resolve({ok: false, message: [...blocked].join(',')}), 1500);
              document.addEventListener('securitypolicyviolation', event => {
                if (event.blockedURI.startsWith('http://127.0.0.1:9')) {
                  blocked.add(event.violatedDirective);
                  if (blocked.has('connect-src') && blocked.has('img-src')) {
                    clearTimeout(timer);
                    resolve({ok: true, message: [...blocked].sort().join(',')});
                  }
                }
              });
              fetch('http://127.0.0.1:9/mostlytext-fetch').catch(() => {});
              const image = new Image();
              image.src = 'http://127.0.0.1:9/mostlytext-image';
            });
            """,
            arguments: [:]
        )
        #expect(result.succeeded)
        #expect(result.message == "connect-src,img-src")
    }
}
