import AppKit
import FileCore
import SwiftUI

/// Inline status for external-file observations. It intentionally sits above
/// the editor without replacing it, so focus stays with the text view.
struct ExternalFileStatusView: View {
    let controller: ExternalFileController

    var body: some View {
        switch controller.notice {
        case .none:
            EmptyView()
        case .reloaded:
            transientStatus(Text("Reloaded from disk"))
                .accessibilityIdentifier("externalReloadStatus")
        case let .moved(url):
            transientStatus(Text("Now following \(url.lastPathComponent)"))
                .accessibilityIdentifier("externalReloadStatus")
        case .conflict:
            conflictBanner
        case let .unavailable(issue):
            unavailableBanner(issue)
        case .monitorFailed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text("Live file monitoring is unavailable for this document.")
                    .font(.callout)
                Button("Retry") {
                    controller.retryMonitoring()
                }
                .accessibilityIdentifier("externalMonitorRetryButton")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
            .background(.yellow.opacity(0.12))
        case let .recoveryCleanup(url):
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                Text(
                    """
                    Recovery for \(url.lastPathComponent) could not be cleaned up. \
                    Keep this window open, or use Save As.
                    """
                )
                .font(.callout)
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("externalRecoveryCleanupRevealButton")
                Button("Retry") {
                    controller.retryRecoveryCleanup()
                }
                .accessibilityIdentifier("externalRecoveryCleanupRetryButton")
                Button("Save As…") {
                    Task { await controller.saveAs() }
                }
                .accessibilityIdentifier("externalRecoveryCleanupSaveAsButton")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
            .background(.red.opacity(0.12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("externalRecoveryCleanupStatus")
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("This file changed on disk. Your local edits are still safe.")
                .font(.callout)
            Spacer()
            Button("Use Disk Version") {
                Task { await controller.resolveConflict(.useExternal) }
            }
            .accessibilityIdentifier("externalConflictUseDiskButton")
            Button("Keep My Changes") {
                Task { await controller.resolveConflict(.keepMine) }
            }
            .accessibilityIdentifier("externalConflictKeepMineButton")
            Button("Not Now") {
                Task { await controller.resolveConflict(.cancel) }
            }
            .accessibilityIdentifier("externalConflictNotNowButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.orange.opacity(0.15))
        // `.contain`: without it, this banner's own identifier silently
        // overrides each button's more-specific identifier instead of just
        // labeling the banner itself (confirmed via a real accessibility-tree
        // dump on an identical pattern elsewhere in this file/target).
        // `.contain` keeps every button independently clickable/identifiable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("externalChangeBanner")
    }

    private func unavailableBanner(_ issue: FileBackingIssue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.red)
            Text(verbatim: unavailableCopy(for: issue))
                .font(.callout)
            Spacer()
            Button("Save As…") {
                Task { await controller.saveAs() }
            }
            .accessibilityIdentifier("externalBackingSaveAsButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.red.opacity(0.12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("externalChangeBanner")
    }

    private func transientStatus(_ text: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
            text
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .foregroundStyle(.secondary)
        .background(.green.opacity(0.1))
        // `.combine`: this banner has no interactive children, so merging
        // it into one element (rather than `.contain`) is safe and is what
        // lets its caller's `.accessibilityIdentifier` actually attach to a
        // real element instead of being silently dropped.
        .accessibilityElement(children: .combine)
    }

    private func unavailableCopy(for issue: FileBackingIssue) -> String {
        switch issue {
        case .missingOrMoved, .parentUnavailable:
            String(localized: "The backing file is unavailable. Save As to keep this copy.")
        case .permissionDenied:
            String(localized: "MostlyText cannot access the backing file. Save As to keep this copy.")
        case .notRegularFile:
            String(localized: "The backing path is no longer a regular file. Save As to keep this copy.")
        case .ambiguousMove, .moveCollidesWithOpenDocument:
            String(localized: "MostlyText cannot safely identify the moved file. Save As to keep this copy.")
        case .readFailed:
            String(localized: "The backing file could not be read safely. Save As to keep this copy.")
        }
    }
}
