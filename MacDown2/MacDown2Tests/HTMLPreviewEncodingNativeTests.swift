import AppKit
import FileCore
import Foundation
@testable import MacDown2
import Preview
import Testing
import WebKit

@MainActor
@Suite("HTML Preview real response encodings", .serialized)
struct HTMLPreviewEncodingNativeTests {
    @Test func fileStoreBOMDocumentsRenderAsUTF8WithoutRewritingOriginalBytes() async throws {
        let source = "<html><head><title>雪 café 😀</title></head><body>Original</body></html>"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let bytes = try bomBytes(source, encoding: encoding)
            let fixture = try HTMLResponseEncodingFixture(sourceBytes: bytes)
            defer { fixture.dispose() }
            #expect(fixture.document.text.utf8.elementsEqual(source.utf8))
            #expect(fixture.document.encoding.encoding == encoding)
            fixture.coordinator.update(
                host: fixture.host, document: fixture.document, tabID: fixture.tabID, owner: fixture.owner
            )
            let view = try await fixture.page(title: "雪 café 😀")
            let handler = try #require(view.configuration.urlSchemeHandler(
                forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
            ) as? BoundedHTMLPreviewHandler)
            #expect(String(data: handler.load.mainData, encoding: .utf8)?.contains("雪 café 😀") == true)
            #expect(try await view.evaluateJavaScript("document.characterSet") as? String == "UTF-8")
            #expect(try Data(contentsOf: fixture.documentURL) == bytes)
        }
    }

    @Test func nonUTF8HTMLResourcesKeepBOMBytesAndAuthoritativeResponseProtection() async throws {
        let title = "資源 café 😀"
        let source = "<html><head><title>\(title)</title></head><body>Resource"
            + "<script>document.title='SCRIPT_EXECUTED'</script></body></html>"
        let fixture = try HTMLResponseEncodingFixture()
        defer { fixture.dispose() }
        for (index, encoding) in [String.Encoding.utf16LittleEndian, .utf16BigEndian].enumerated() {
            let name = "resource-\(index).html"
            let bytes = try bomBytes(source, encoding: encoding)
            try bytes.write(to: fixture.folder.appendingPathComponent(name))
            let (view, observer) = try await fixture.boundedPage(relativePath: name)
            try await fixture.wait { view.title == title && !view.isLoading }
            let record = try #require(observer.record(for: view.url))
            let response = try #require(record.response as? HTTPURLResponse)
            #expect(response.mimeType == "text/html")
            #expect(response.value(forHTTPHeaderField: "Content-Type") == "text/html")
            #expect(response.value(forHTTPHeaderField: "Content-Security-Policy")
                == PreviewSecurity.contentSecurityPolicy)
            #expect(record.bytes == bytes)
            #expect(record.finished && !record.failed)
            #expect(view.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
            #expect(try await view.evaluateJavaScript("document.title") as? String == title)
            #expect(try Data(contentsOf: fixture.folder.appendingPathComponent(name)) == bytes)
        }
    }

    @Test func realSubresourcesKeepTheirMIMETypesAndUnknownHTMLIsNotAnImage() async throws {
        let fixture = try HTMLResponseEncodingFixture(sourceBytes: Data("""
        <html><head><title>Typed resources</title></head><body>
        <img id="ordinary" src="image.png"><img id="vector" src="vector.svg">
        <img id="xml" src="vector.xml"><img id="unknown" src="payload.mostlytextunknown">
        </body></html>
        """.utf8))
        defer { fixture.dispose() }
        let png = try SecuredMarkdownMountedTests().smallPNG()
        let svg = try bomBytes("""
        <?xml version="1.0" encoding="UTF-16"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="9" height="5"><rect width="9" height="5" fill="blue"/></svg>
        """, encoding: .utf16LittleEndian)
        let unknown = Data("<html><script>document.title='UNSAFE'</script></html>".utf8)
        let resources = [
            ("image.png", png), ("vector.svg", svg), ("vector.xml", svg),
            ("payload.mostlytextunknown", unknown),
        ]
        for (name, bytes) in resources {
            try bytes.write(to: fixture.folder.appendingPathComponent(name))
        }
        let (view, observer) = try await fixture.boundedPage()
        try await fixture.wait { view.title == "Typed resources" && !view.isLoading }
        let observed = try await view.evaluateJavaScript("""
        JSON.stringify(Array.from(document.images, image =>
          ({id:image.id, complete:image.complete, width:image.naturalWidth, height:image.naturalHeight})))
        """)
        let json = try #require(observed as? String)
        let images = try JSONDecoder().decode([ObservedPreviewImage].self, from: Data(json.utf8))
        #expect(images.count == 4 && images.allSatisfy(\.complete))
        #expect(images.first { $0.id == "ordinary" }?.width == 8)
        #expect(images.first { $0.id == "vector" }?.width == 9)
        #expect(images.first { $0.id == "vector" }?.height == 5)
        #expect(images.first { $0.id == "unknown" }?.width == 0)
        try assertResponse("image.png", mime: "image/png", bytes: png, observer: observer)
        try assertResponse("vector.svg", mime: "image/svg+xml", bytes: svg, observer: observer)
        try assertResponse("vector.xml", mime: "application/xml", bytes: svg, observer: observer)
        try assertResponse("payload.mostlytextunknown", mime: "application/octet-stream", bytes: unknown,
                           observer: observer)
    }

    private func bomBytes(_ source: String, encoding: String.Encoding) throws -> Data {
        let body = try #require(source.data(using: encoding))
        return Data(encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]) + body
    }

    private func assertResponse(
        _ name: String, mime: String, bytes: Data, observer: ObservedHTMLScheme
    ) throws {
        let record = try #require(observer.records.first { $0.request.url?.lastPathComponent == name })
        let response = try #require(record.response as? HTTPURLResponse)
        #expect(response.mimeType == mime)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == mime)
        #expect(response.value(forHTTPHeaderField: "Content-Security-Policy") == PreviewSecurity.contentSecurityPolicy)
        #expect(record.finished && !record.failed)
        #expect(record.bytes == bytes)
    }
}

private struct ObservedPreviewImage: Decodable {
    let id: String
    let complete: Bool
    let width: Int
    let height: Int
}
