import Foundation

/// The OS-level document-type contract for MacDown 2, mirroring
/// `project.yml`'s `CFBundleDocumentTypes`/`UTExportedTypeDeclarations`.
///
/// `FileFormatRegistry` is the runtime source of truth for formats; this
/// manifest is the *declared* source of truth for what the OS is told the app
/// can open. `FormatRegistryConsistency` detects drift between the two so no
/// implementation slice advertises a format the app cannot actually open.
public struct FormatManifest: Sendable, Equatable {
    /// One `CFBundleDocumentTypes` entry.
    public struct DocumentTypeDeclaration: Sendable, Equatable {
        public let formatID: String
        public let role: String
        public let itemContentTypes: [String]
        public let extensions: [String]

        public init(formatID: String, role: String, itemContentTypes: [String], extensions: [String]) {
            self.formatID = formatID
            self.role = role
            self.itemContentTypes = itemContentTypes
            self.extensions = extensions
        }
    }

    public let documentTypes: [DocumentTypeDeclaration]

    public init(documentTypes: [DocumentTypeDeclaration]) {
        self.documentTypes = documentTypes
    }

    /// Keep in sync with `project.yml` `CFBundleDocumentTypes` (and the TOML
    /// exported declaration). `FormatRegistryConsistencyTests` compares this
    /// against `FileFormatRegistry.defaultFormats`.
    public static let current = FormatManifest(documentTypes: [
        DocumentTypeDeclaration(
            formatID: "markdown",
            role: "Editor",
            itemContentTypes: ["net.daringfireball.markdown", "app.mostlytext.markdown-alias"],
            extensions: ["md", "markdown", "mdown", "mkd", "mkdn"]
        ),
        DocumentTypeDeclaration(
            formatID: "html",
            role: "Editor",
            itemContentTypes: ["public.html"],
            extensions: ["html", "htm"]
        ),
        DocumentTypeDeclaration(
            formatID: "json",
            role: "Editor",
            itemContentTypes: ["public.json"],
            extensions: ["json"]
        ),
        DocumentTypeDeclaration(
            formatID: "yaml",
            role: "Editor",
            itemContentTypes: ["public.yaml"],
            extensions: ["yaml", "yml"]
        ),
        DocumentTypeDeclaration(
            formatID: "toml",
            role: "Editor",
            itemContentTypes: ["com.joncallim.macdown2.toml"],
            extensions: ["toml"]
        ),
        DocumentTypeDeclaration(
            formatID: "plaintext",
            role: "Editor",
            itemContentTypes: ["public.plain-text"],
            extensions: ["txt"]
        ),
        DocumentTypeDeclaration(
            formatID: "source",
            role: "Alternate",
            itemContentTypes: ["public.source-code"],
            extensions: [
                "js", "jsx", "ts", "tsx", "py", "rb", "css", "swift",
                "c", "cpp", "cc", "cxx", "h", "hpp", "sh", "bash", "zsh",
                "sql", "xml", "tex", "latex",
            ]
        ),
    ])
}

/// Consistency validation between the runtime format registry and the
/// declared OS manifest. Returns a report of issues; an empty report means no
/// drift.
public enum FormatRegistryConsistency {
    public struct Report: Sendable, Equatable {
        public var issues: [String]
        public var isConsistent: Bool {
            issues.isEmpty
        }

        public init(issues: [String] = []) {
            self.issues = issues
        }
    }

    /// - Parameters:
    ///   - registry: the runtime format registry.
    ///   - manifest: the declared document-type manifest.
    ///   - highlightLanguageSupported: verdict for a highlight language id
    ///     (e.g. `GrammarRegistry.supportedLanguageIDs.contains`); `nil` ids
    ///     are always acceptable.
    public static func validate(
        registry: FileFormatRegistry,
        manifest: FormatManifest,
        highlightLanguageSupported: (String?) -> Bool
    ) -> Report {
        var issues: [String] = []
        issues += extensionOwnershipIssues(registry: registry, manifest: manifest)
        issues += previewCapabilityIssues(registry: registry)
        issues += highlightLanguageIssues(
            registry: registry,
            highlightLanguageSupported: highlightLanguageSupported
        )
        return Report(issues: issues)
    }

    /// Every registered extension must be declared exactly once, and every
    /// declared extension must be registered by a format.
    private static func extensionOwnershipIssues(
        registry: FileFormatRegistry,
        manifest: FormatManifest
    ) -> [String] {
        var issues: [String] = []
        var extensionOwners: [String: String] = [:]
        for format in registry.formats {
            for ext in format.extensions {
                if let previous = extensionOwners[ext] {
                    issues.append("Extension '\(ext)' is registered by both '\(previous)' and '\(format.id)'")
                } else {
                    extensionOwners[ext] = format.id
                }
            }
        }
        let declaredExtensions = Set(manifest.documentTypes.flatMap(\.extensions))
        for ext in declaredExtensions where extensionOwners[ext] == nil {
            issues.append("Declared extension '\(ext)' has no registered format")
        }
        for ext in extensionOwners.keys where !declaredExtensions.contains(ext) {
            issues.append("Registered extension '\(ext)' is not declared in the manifest")
        }
        return issues
    }

    /// Preview capability invariants: a capability must have a default mode;
    /// a none capability must have neither.
    private static func previewCapabilityIssues(registry: FileFormatRegistry) -> [String] {
        var issues: [String] = []
        for format in registry.formats {
            switch format.previewCapability {
            case .none:
                if format.defaultPreviewMode != nil {
                    issues.append("\(format.id): .none capability must not declare a default preview mode")
                }
                if !format.supportedPreviewModes.isEmpty {
                    issues.append("\(format.id): .none capability must not declare supported preview modes")
                }
            case .markdown, .htmlSourceAndRendered, .jsonOutline:
                if format.defaultPreviewMode == nil {
                    issues.append(
                        "\(format.id): capability \(format.previewCapability) "
                            + "must declare a default preview mode"
                    )
                }
                if format.supportedPreviewModes.isEmpty {
                    issues.append(
                        "\(format.id): capability \(format.previewCapability) "
                            + "must declare supported preview modes"
                    )
                }
            }
        }
        return issues
    }

    /// Highlighting: a language id the registry cannot satisfy is drift.
    private static func highlightLanguageIssues(
        registry: FileFormatRegistry,
        highlightLanguageSupported: (String?) -> Bool
    ) -> [String] {
        var issues: [String] = []
        for format in registry.formats {
            if let id = format.highlightLanguageID, !highlightLanguageSupported(id) {
                issues.append("\(format.id): highlight language '\(id)' is not supported by the grammar registry")
            }
        }
        return issues
    }
}
