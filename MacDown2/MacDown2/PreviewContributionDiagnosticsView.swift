import Contributions
import SwiftUI

/// A compact, non-modal indicator for Preview's contribution diagnostics
/// (architecture takeover, pass 9/10). Never a modal alert: Preview
/// recomputes on every keystroke, so a blocking alert would interrupt
/// typing. Sits beside `PreviewBusyIndicator` in one overlay container so
/// the two never overlap each other.
struct PreviewContributionDiagnosticsBadge: View {
    let diagnostics: [PreviewContributionDiagnostic]

    @State private var isPresented = false

    private var highestSeverity: ContributionDiagnostic.Severity? {
        if diagnostics.contains(where: { $0.severity == .error }) {
            return .error
        }
        return diagnostics.isEmpty ? nil : .warning
    }

    var body: some View {
        if let highestSeverity {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: highestSeverity == .error ? "exclamationmark.octagon.fill" :
                        "exclamationmark.triangle.fill")
                    Text("\(diagnostics.count)")
                }
                .font(.caption)
                .foregroundStyle(highestSeverity == .error ? Color.red : Color.yellow)
                .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("previewDiagnosticsBadge")
            .accessibilityLabel(accessibilityLabel(for: highestSeverity))
            .popover(isPresented: $isPresented) {
                PreviewContributionDiagnosticsList(diagnostics: diagnostics)
            }
        }
    }

    private func accessibilityLabel(for severity: ContributionDiagnostic.Severity) -> String {
        switch severity {
        case .error: PreviewDiagnosticLabel.error(count: diagnostics.count).message()
        case .warning: PreviewDiagnosticLabel.warning(count: diagnostics.count).message()
        }
    }
}

/// The diagnostics list a badge activation opens, in the same deterministic
/// result/diagnostic order the composer produced them in.
private struct PreviewContributionDiagnosticsList: View {
    let diagnostics: [PreviewContributionDiagnostic]

    var body: some View {
        List(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
            VStack(alignment: .leading, spacing: 2) {
                // A technical contribution identifier (e.g. "math", "mermaid"), never translated.
                Text(verbatim: diagnostic.contributionID)
                    .font(.caption.bold())
                Text(verbatim: diagnostic.message)
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("previewDiagnosticRow")
        }
        .frame(minWidth: 280, minHeight: 120)
        .accessibilityIdentifier("previewDiagnosticsList")
    }
}
