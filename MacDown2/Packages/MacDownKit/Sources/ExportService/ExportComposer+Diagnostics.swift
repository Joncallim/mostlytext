import Foundation

/// Enforces fatal derived-content and target resource policy before publication.
extension ExportComposer {
    static func resolve(
        derived: [ExportDiagnostic],
        resources: [ExportDiagnostic],
        rendered: CMarkGFM.Rendered,
        policy: Policy
    ) throws -> [ExportDiagnostic] {
        let fatal = derived.filter(\.preventsPublication)
        guard fatal.isEmpty else { throw ExportError.derivedContentUnavailable(fatal) }
        if rendered.containsRawHTML, case .reject = policy.rawHTML {
            throw ExportError.rawHTMLNotEmbeddable
        }

        // Only unresolved resources close the export. A failed derived
        // contribution is never fatal on its own: its authored Markdown is still
        // in the body, and its diagnostic is already recorded.
        let unresolved = resources.filter { $0.severity == .error }
        if policy.unresolvedResourcesAreFatal, !unresolved.isEmpty {
            throw ExportError.unresolvedResources(unresolved)
        }

        guard rendered.containsRawHTML, case .preserveWithWarning = policy.rawHTML else {
            return derived + resources
        }
        let bestEffort = ExportDiagnostic(
            severity: .warning,
            message: String(localized: """
            Authored raw HTML is rendered best-effort by the print system; it cannot load scripts or \
            remote resources.
            """, bundle: .module)
        )
        return derived + resources + [bestEffort]
    }
}
