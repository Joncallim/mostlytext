import Foundation
import SwiftTreeSitterLayer

/// Builds an immutable Markdown tree on the calling executor. A large-file
/// owner may call this from a detached task and transfer only the Sendable
/// snapshot to its main-actor section cache; no live parser crosses actors.
enum MarkdownSectionParser {
    enum ParseError: Error {
        case grammarUnavailable
        case snapshotUnavailable
    }

    static func snapshot(source: String, registry: GrammarRegistry) throws -> LanguageLayerTreeSnapshot {
        guard let markdown = registry.configuration(for: "markdown") else {
            throw ParseError.grammarUnavailable
        }
        let layer = try LanguageLayer(
            languageConfig: markdown,
            configuration: .init(languageProvider: registry.languageProvider)
        )
        _ = layer.replaceContent(with: source)
        guard let snapshot = layer.snapshot() else { throw ParseError.snapshotUnavailable }
        return snapshot
    }
}
