import AppSettings
import SwiftUI

struct LegacyMigrationPolicyNotes: View {
    let source: LegacyPreferenceSnapshot

    var body: some View {
        let entries = LegacyPreferenceReport(snapshot: source).entries.filter {
            switch $0.disposition {
            case .currentCapabilityPolicy, .requiresFreshUpdateConsent: true
            default: false
            }
        }
        if !entries.isEmpty {
            DisclosureGroup("Other Migration Policies") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entries, id: \.key) { entry in
                        switch entry.disposition {
                        case let .currentCapabilityPolicy(policy, value):
                            VStack(alignment: .leading, spacing: 4) {
                                Text(explanation(policy))
                                Text(value ? LocalizedStringKey("Previously enabled") :
                                    LocalizedStringKey("Previously disabled"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        case let .requiresFreshUpdateConsent(value):
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    LocalizedStringKey("Update channels require fresh consent. " +
                                        "No old feed, key or pre-release choice is imported.")
                                )
                                Text(value ? LocalizedStringKey("Pre-release updates were previously enabled.") :
                                    LocalizedStringKey("Pre-release updates were previously disabled."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        default: EmptyView()
                        }
                    }
                }.padding(.top, 8)
            }
        }
    }

    private func explanation(_ policy: LegacyPreferenceReport.CapabilityPolicy) -> LocalizedStringKey {
        switch policy {
        case .localMath:
            "Math uses the local engine. Old MathJax settings do not disable it or load a remote runtime."
        case .currentInlineDollarRules:
            "The old inline-dollar switch is not imported. This version uses its current math parsing rules."
        case .localGraphviz:
            "Graphviz is a local capability; old scripts and renderer switches are not imported."
        case .localMermaid:
            "Mermaid is a local capability; old scripts and renderer switches are not imported."
        case .explicitTableOfContents:
            "A table of contents requires an explicit [TOC] marker. Migration does not insert or rewrite document text."
        }
    }
}
