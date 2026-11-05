import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterHTML
import TreeSitterJavaScript
import TreeSitterJavaScriptResources
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources
import TreeSitterPython
import TreeSitterRuby
import TreeSitterSQL
import TreeSitterSQLResources
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTypeScript
import TreeSitterXML
import TreeSitterYAML

extension ConfigurationCache {
    // MARK: Grammar build recipes

    /// Build recipes per known language id.
    ///
    /// A table keeps the 14-case dispatch reviewable and uniform; an id that
    /// is not in the table resolves to `nil` (explicit no-highlight, never a
    /// silent default). Languages whose upstream grammar ships no fixed-source
    /// manifest or generated parser are vendored locally and resolved through
    /// their `TreeSitterXResources` query bundles instead of an SPM resource
    /// bundle.
    private static let grammarFactories: [String: @Sendable () throws -> LanguageConfiguration?] = [
        "markdown": {
            guard let queriesURL = TreeSitterMarkdownResources.queriesURL else { return nil }
            return try configuration(
                language: Language(tree_sitter_markdown()),
                name: "Markdown",
                queriesURL: queriesURL
            )
        },
        "markdown_inline": {
            guard let queriesURL = TreeSitterMarkdownInlineResources.queriesURL else { return nil }
            guard var config = try configuration(
                language: Language(tree_sitter_markdown_inline()),
                name: "MarkdownInline",
                queriesURL: queriesURL
            ) else { return nil }
            // Valid UTF-16 edits can otherwise retain a different inline tree
            // from a fresh parse. Keep the complete source/capture semantics.
            config.reusesPreviousTree = false
            return config
        },
        "json": {
            try configuration(
                language: Language(tree_sitter_json()),
                name: "JSON",
                bundleName: "TreeSitterJSON_TreeSitterJSON"
            )
        },
        "html": {
            try configuration(
                language: Language(tree_sitter_html()),
                name: "HTML",
                bundleName: "TreeSitterHTML_TreeSitterHTML"
            )
        },
        "yaml": {
            try configuration(
                language: Language(tree_sitter_yaml()),
                name: "YAML",
                bundleName: "TreeSitterYAML_TreeSitterYAML"
            )
        },
        "toml": {
            try configuration(
                language: Language(tree_sitter_toml()),
                name: "TOML",
                bundleName: "TreeSitterTOML_TreeSitterTOML"
            )
        },
        "javascript": {
            // Vendored local grammar (upstream ships no fixed-sources manifest).
            guard let queriesURL = TreeSitterJavaScriptResources.queriesURL else { return nil }
            return try configuration(
                language: Language(tree_sitter_javascript()),
                name: "JavaScript",
                queriesURL: queriesURL
            )
        },
        "typescript": {
            try configuration(
                language: Language(tree_sitter_typescript()),
                name: "TypeScript",
                bundleName: "TreeSitterTypeScript_TreeSitterTypeScript"
            )
        },
        "python": {
            try configuration(
                language: Language(tree_sitter_python()),
                name: "Python",
                bundleName: "TreeSitterPython_TreeSitterPython"
            )
        },
        "ruby": {
            try configuration(
                language: Language(tree_sitter_ruby()),
                name: "Ruby",
                bundleName: "TreeSitterRuby_TreeSitterRuby"
            )
        },
        "css": {
            try configuration(
                language: Language(tree_sitter_css()),
                name: "CSS",
                bundleName: "TreeSitterCSS_TreeSitterCSS"
            )
        },
        "swift": {
            try configuration(
                language: Language(tree_sitter_swift()),
                name: "Swift",
                bundleName: "TreeSitterSwift_TreeSitterSwift"
            )
        },
        "cpp": {
            try configuration(
                language: Language(tree_sitter_cpp()),
                name: "C/C++",
                bundleName: "TreeSitterCPP_TreeSitterCPP"
            )
        },
        "bash": {
            try configuration(
                language: Language(tree_sitter_bash()),
                name: "Bash",
                bundleName: "TreeSitterBash_TreeSitterBash"
            )
        },
        "sql": {
            // Vendored local grammar (upstream ships no generated parser.c).
            guard let queriesURL = TreeSitterSQLResources.queriesURL else { return nil }
            return try configuration(
                language: Language(tree_sitter_sql()),
                name: "SQL",
                queriesURL: queriesURL
            )
        },
        "xml": {
            try configuration(
                language: Language(tree_sitter_xml()),
                name: "XML",
                bundleName: "TreeSitterXML_TreeSitterXML"
            )
        },
    ]

    /// Resolves a factory for the language id and builds it. Returns `nil` for
    /// an id with no recipe (explicit no-highlight, never a silent default).
    func buildConfiguration(for id: String) throws -> LanguageConfiguration? {
        guard let factory = Self.grammarFactories[id] else { return nil }
        return try factory()
    }

    private static func configuration(
        language: Language,
        name: String,
        queriesURL: URL
    ) throws -> LanguageConfiguration? {
        let queries = try Self.loadQueries(for: language, in: queriesURL)
        return LanguageConfiguration(language, name: name, queries: queries)
    }

    private static func configuration(
        language: Language,
        name: String,
        bundleName: String
    ) throws -> LanguageConfiguration? {
        guard let queriesURL = Self.queriesURL(bundleName: bundleName) else {
            return nil
        }
        return try configuration(language: language, name: name, queriesURL: queriesURL)
    }

    /// Manually enumerate query `.scm` files and compile them.
    ///
    /// This avoids a `FileManager.enumerator` quirk where requesting the
    /// `isReadableKey` resource key causes some dependency resource bundles to
    /// enumerate as empty even though their files are readable.
    private static func loadQueries(
        for language: Language,
        in queriesURL: URL
    ) throws -> [Query.Definition: Query] {
        // Note: `[.skipsHiddenFiles]` causes `contentsOfDirectory` to return empty
        // for some dependency resource bundles, so we enumerate all entries.
        let files = try FileManager.default.contentsOfDirectory(at: queriesURL,
                                                                includingPropertiesForKeys: nil,
                                                                options: [])
        var queries = [Query.Definition: Query]()
        for fileURL in files where fileURL.pathExtension == "scm" && !fileURL.lastPathComponent.hasPrefix(".") {
            let query = try Query(language: language, url: fileURL)
            let definition: Query.Definition
            switch fileURL.lastPathComponent {
            case Query.Definition.injections.filename:
                definition = .injections
            case Query.Definition.highlights.filename:
                definition = .highlights
            case Query.Definition.locals.filename:
                definition = .locals
            default:
                let filename = fileURL.lastPathComponent.replacingOccurrences(of: ".scm", with: "")
                definition = .custom(filename)
            }
            queries[definition] = query
        }
        return queries
    }

    /// Locates the tree-sitter query directory for a resource bundle.
    ///
    /// In app builds the bundle is nested in `Bundle.main`. In SPM test targets
    /// `Bundle.main` points at the SwiftPM runner, so we fall back to the
    /// directory that contains the test bundle / executable that links the
    /// SwiftTreeSitter parser classes.
    private static func queriesURL(bundleName: String) -> URL? {
        let parserBundleDir = Bundle(for: Parser.self).bundleURL.deletingLastPathComponent()
        let mainDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let bundleCandidates = [
            Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName).bundle"),
            parserBundleDir.appendingPathComponent("\(bundleName).bundle"),
            mainDir.appendingPathComponent("\(bundleName).bundle"),
            mainDir.deletingLastPathComponent().appendingPathComponent("\(bundleName).bundle"),
        ]

        for bundleURL in bundleCandidates {
            guard let bundleURL else { continue }

            // Xcode app bundles place resources under Contents/Resources;
            // SPM debug builds place them directly under the bundle root.
            let queriesCandidates = [
                bundleURL.appendingPathComponent("queries", isDirectory: true),
                bundleURL.appendingPathComponent("Contents/Resources/queries", isDirectory: true),
            ]
            for queriesURL in queriesCandidates where FileManager.default.fileExists(atPath: queriesURL.path) {
                return queriesURL
            }

            // Some grammar packages copy a nested queries directory (e.g.
            // tree-sitter-xml copies `queries/xml`), which lands in the bundle
            // as a single top-level directory holding the `.scm` files
            // directly. Find it so the XML grammar (and any future grammar
            // packaged the same way) resolves its queries.
            if let nested = nestedQueriesDirectory(in: bundleURL) {
                return nested
            }
        }

        return nil
    }

    /// Returns the first top-level subdirectory of a resource bundle that
    /// contains at least one `.scm` query file, or `nil`.
    private static func nestedQueriesDirectory(in bundleURL: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return nil
        }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let scmFiles = (try? FileManager.default.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: nil,
                options: []
            )) ?? []
            if scmFiles.contains(where: { $0.pathExtension == "scm" }) {
                return entry
            }
        }
        return nil
    }
}
