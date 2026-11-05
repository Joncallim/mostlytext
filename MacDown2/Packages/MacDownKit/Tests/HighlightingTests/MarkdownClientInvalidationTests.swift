import Foundation
#if canImport(Neon)
    import Neon
#else
    import OwnedStylingCore
#endif
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing
import TreeSitterClient
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources

@Suite("Markdown client sublayer invalidation", .serialized)
struct MarkdownClientInvalidationTests {
    enum EditShape: CaseIterable {
        case replacement, removeMarkup, removeAll
    }

    @MainActor
    final class Source {
        var text: String
        var callback: (() -> Void)?
        var reading = false
        var observations: [[NamedRange]] = []
        var callbackCount = 0
        var errors: [String] = []

        init(_ text: String) {
            self.text = text
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: EditShape.allCases, [false, true])
    func warmedClientMatchesFreshAfterEdit(_ shape: EditShape, reentrant: Bool) async throws {
        for ending in ["\n", "\r\n", "\r"] {
            let state = Source(fixture(ending))
            let client = try await warmedClient(state, expectsInline: true)
            if reentrant {
                state.callback = { [weak client, weak state] in
                    guard let client, let state, !state.reading else { return }
                    state.reading = true
                    defer { state.reading = false }
                    do {
                        state.callbackCount += 1
                        let snapshot: [NamedRange]? = try client.highlights(
                            in: NSRange(location: 0, length: state.text.utf16.count),
                            provider: state.text.predicateTextProvider, mode: .required
                        )
                        if let snapshot {
                            state.observations.append(snapshot)
                        }
                    } catch { state.errors.append(String(describing: error)) }
                }
            }
            edit(shape, client: client, state: state)
            let freshSource = Source(state.text)
            let expectedClient = try await warmedClient(freshSource, expectsInline: shape != .removeAll)
            let expected = try captures(expectedClient, freshSource)
            let actual = try await completeCaptures(client, state)
            #expect(actual == expected)
            #expect(state.errors.isEmpty)
            if reentrant {
                #expect(state.callbackCount > 0)
                #expect(state.observations.allSatisfy { $0 == expected })
            }
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func asyncQueryRejectsReentrantContentChange() async throws {
        let state = Source(fixture("\n"))
        let client = try makeClient(state, probe: ClientResolutionProbe())
        var edited = false
        state.callback = { [weak client, weak state] in
            guard let client, let state, !edited else { return }
            edited = true
            state.callback = nil
            edit(.replacement, client: client, state: state)
        }
        await #expect(throws: CancellationError.self) {
            try await completeCaptures(client, state)
        }
        #expect(edited)
        let fresh = Source(state.text)
        let expected = try await warmedClient(fresh, expectsInline: true)
        #expect(try await completeCaptures(client, state) == completeCaptures(expected, fresh))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func queryPastDocumentEndOnlyValidatesExistingContent() async throws {
        let state = Source(fixture("\n"))
        let client = try await warmedClient(state, expectsInline: true)
        let expected = try await completeCaptures(client, state)
        let actual = try await client.highlights(
            in: NSRange(location: 0, length: state.text.utf16.count + 64),
            provider: state.text.predicateTextProvider, mode: .required
        )
        #expect(actual == expected)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func partialTokenApplicationPreservesStylesOutsideItsQuery() async throws {
        let source = Source("*aa **bold** cc*\n")
        let client = try await warmedClient(source, expectsInline: true)
        let provider = client.tokenProvider(with: source.text.predicateTextProvider)
        let fullRange = NSRange(location: 0, length: source.text.utf16.count)
        let full = try #require(provider.sync(fullRange))
        var reference = [String?](repeating: nil, count: fullRange.length)
        paint(full, into: &reference)
        let partialRange = NSRange(location: 1, length: 2)
        let partial = try #require(provider.sync(partialRange))
        #expect(!partial.tokens.isEmpty)
        #expect(partial.tokens.allSatisfy { NSIntersectionRange($0.range, partialRange) == $0.range })
        var actual = reference
        paint(partial, into: &actual)
        #expect(actual == reference)
    }

    private func paint(_ application: TokenApplication, into styles: inout [String?]) {
        if let range = application.range {
            for index in range.location ..< min(NSMaxRange(range), styles.count) {
                styles[index] = nil
            }
        }
        for token in application.tokens {
            for index in token.range.location ..< min(NSMaxRange(token.range), styles.count) {
                styles[index] = token.name
            }
        }
    }

    private func fixture(_ ending: String) -> String {
        let block = """
        # Heading with `code`

        Some *emphasis*, **strong** and a [link](https://example.com).
        Unicode café é 👩🏽‍💻 and `inline`.

        ```
        fenced code line
        ```


        """.replacingOccurrences(of: "\n", with: ending)
        return String(repeating: block, count: 8)
    }

    @MainActor
    private func edit(_ shape: EditShape, client: TreeSitterClient, state: Source) {
        let text = state.text as NSString
        let range: NSRange
        let replacement: String
        switch shape {
        case .replacement:
            range = NSRange(location: text.length / 2, length: 600)
            replacement = text.substring(with: range) + "y"
        case .removeMarkup:
            range = NSRange(location: text.length / 2, length: 600)
            replacement = String(repeating: "plain text ", count: 30)
        case .removeAll:
            range = NSRange(location: 0, length: text.length)
            replacement = "````\nplain\n````\n"
        }
        client.willChangeContent(in: range)
        state.text = text.replacingCharacters(in: range, with: replacement)
        client.didChangeContent(in: range, delta: replacement.utf16.count - range.length)
    }

    @MainActor
    private func makeClient(_ state: Source, probe: ClientResolutionProbe) throws -> TreeSitterClient {
        let blockURL = try #require(TreeSitterMarkdownResources.queriesURL)
        let inlineURL = try #require(TreeSitterMarkdownInlineResources.queriesURL)
        let block = try LanguageConfiguration(tree_sitter_markdown(), name: "Markdown", queriesURL: blockURL)
        let inline = try LanguageConfiguration(
            tree_sitter_markdown_inline(), name: "MarkdownInline", queriesURL: inlineURL
        )
        let configuration = TreeSitterClient.Configuration(
            languageProvider: { name in
                guard name == "markdown_inline" else { return nil }
                probe.markStarted()
                return inline
            },
            contentProvider: { .init(string: state.text, limit: $0) },
            contentSnapshopProvider: { .init(string: state.text, limit: $0) },
            lengthProvider: { state.text.utf16.count },
            invalidationHandler: { _ in
                probe.signalAfterResolution()
                state.callback?()
            },
            locationTransformer: { point($0, in: state.text) }
        )
        return try TreeSitterClient(rootLanguageConfig: block, configuration: configuration)
    }

    @MainActor
    private func warmedClient(_ state: Source, expectsInline: Bool) async throws -> TreeSitterClient {
        let probe = ClientResolutionProbe()
        let client = try makeClient(state, probe: probe)
        _ = try optionalCaptures(client, state)
        if expectsInline {
            // The first synchronous query may enqueue inline resolution. Wait
            // for its completion publication, not a timing-based quiet period.
            _ = try #require(await probe.events.first { @Sendable _ in true })
        }
        let warmed = try await completeCaptures(client, state)
        if expectsInline {
            #expect(warmed.contains { $0.name == "markup.bold" })
        }
        return client
    }

    @MainActor
    private func completeCaptures(_ client: TreeSitterClient, _ source: Source) async throws -> [NamedRange] {
        try await client.highlights(
            in: NSRange(location: 0, length: source.text.utf16.count),
            provider: source.text.predicateTextProvider, mode: .required
        )
    }

    @MainActor
    private func optionalCaptures(_ client: TreeSitterClient, _ source: Source) throws -> [NamedRange]? {
        try client.highlights(
            in: NSRange(location: 0, length: source.text.utf16.count),
            provider: source.text.predicateTextProvider, mode: .required
        )
    }

    @MainActor
    private func captures(_ client: TreeSitterClient, _ source: Source) throws -> [NamedRange] {
        let result: [NamedRange]? = try client.highlights(
            in: NSRange(location: 0, length: source.text.utf16.count),
            provider: source.text.predicateTextProvider, mode: .required
        )
        return try #require(result)
    }

    private func point(_ location: Int, in text: String) -> Point {
        let prefix = Array(text.utf16.prefix(location))
        let row = prefix.filter { $0 == 10 }.count
        let start = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
        return Point(row: row, column: (location - start) * 2)
    }
}

/// The language provider can run on the parser queue; keep this test signal
/// independent of the source's main-actor state.
private final class ClientResolutionProbe: @unchecked Sendable {
    let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var started = false

    init() {
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = channel.stream
        continuation = channel.continuation
    }

    deinit { continuation.finish() }

    func markStarted() {
        lock.lock()
        started = true
        lock.unlock()
    }

    func signalAfterResolution() {
        lock.lock()
        let ready = started
        lock.unlock()
        if ready {
            continuation.yield(())
        }
    }
}
