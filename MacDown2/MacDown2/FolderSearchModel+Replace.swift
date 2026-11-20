import FileCore
import Foundation
import TextSearch

typealias FolderReplaceRunner = @Sendable (
    URL,
    [ReplacementPlan],
    @escaping @Sendable (String) async -> Bool,
    @escaping @Sendable (ReplacementFileResult) async -> Void
) async -> [ReplacementFileResult]

typealias FolderReplacePreviewBuilder = @Sendable (URL, ReplacementPlan) async -> ReplacementFilePreview

/// What a finished Replace in Folder did, kept on screen after the follow-up
/// re-search so the user can see which files were skipped and why.
struct FolderReplaceSummary: Equatable {
    var replacedMatches: Int
    var replacedFiles: Int
    var skipped: [ReplacementFileResult]
}

/// Replace in Folder (EPIC-22 §6.16, Slice 7c): a previewed, per-file
/// selectable, explicitly confirmed rewrite of the files the current search
/// found. All disk safety (revision re-verification, conditional
/// publication, symlink and unsaved-document refusal) lives in
/// `WorkspaceReplaceEngine`; this extension is only the review/confirm
/// state machine around it.
extension FolderSearchModel {
    static func makeReplaceEngine() -> (run: FolderReplaceRunner, preview: FolderReplacePreviewBuilder) {
        let engine = WorkspaceReplaceEngine()
        return (
            { root, plans, isProtected, onResult in
                await engine.replace(root: root, plans: plans, isProtected: isProtected, onResult: onResult)
            },
            { root, plan in await engine.preview(root: root, plan: plan) }
        )
    }

    var includedResults: [FolderSearchMatch] {
        results.filter { !excludedPaths.contains($0.relativePath) }
    }

    var includedMatchCount: Int {
        includedResults.reduce(0) { $0 + $1.matches.count }
    }

    /// Replace is only offered against a complete result set: a truncated
    /// search would silently leave matches beyond the cap unreplaced while
    /// the user believed the whole folder was done.
    /// Files the search could not read or decode (e.g. not UTF-8). Replace
    /// never touches them, so the user must be told the run is not exhaustive.
    var unsearchedFileCount: Int {
        switch outcome {
        case let .completed(_, skipped, _), let .truncated(_, skipped, _),
             let .timedOut(_, skipped, _): skipped
        default: 0
        }
    }

    var canReplace: Bool {
        guard !isReplacing, !isSearching, root != nil, !includedResults.isEmpty else { return false }
        if case .completed = outcome {
            return true
        }
        return false
    }

    func setIncluded(_ isIncluded: Bool, path: String) {
        if isIncluded {
            excludedPaths.remove(path)
        } else {
            excludedPaths.insert(path)
        }
    }

    /// A SwiftUI row can survive a search refresh briefly. Its checkbox must
    /// never change inclusion for a newer match at the same path.
    func setIncluded(_ isIncluded: Bool, result: PresentedResult) {
        guard isCurrentResult(result) else { return }
        setIncluded(isIncluded, path: result.match.relativePath)
    }

    func isIncluded(path: String) -> Bool {
        !excludedPaths.contains(path)
    }

    func requestReplace() {
        guard canReplace else { return }
        isConfirmingReplace = true
    }

    func togglePreview(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadPreview(path: path)
        }
    }

    func togglePreview(result: PresentedResult) {
        guard isCurrentResult(result) else { return }
        togglePreview(path: result.match.relativePath)
    }

    func cancelReplace() {
        replaceTask?.cancel()
    }

    /// The root this run was authorised against is going away: cancel it and
    /// make sure nothing it later reports is published against the new root
    /// (#183 F14). Files already written stay written; the engine stops at the
    /// next file boundary.
    func retireReplaceRun() {
        replaceGeneration += 1
        replaceTask?.cancel()
        replaceTask = nil
        isReplacing = false
        replaceSummary = nil
    }

    func confirmReplace() {
        isConfirmingReplace = false
        guard canReplace, let root else { return }
        let plans = includedResults.map { ReplacementPlan($0, replacementText: replacement) }
        isReplacing = true
        replaceSummary = nil
        replaceCompleted = 0
        replaceTotal = plans.count
        let hasUnsaved = hasUnsavedOpenDocument
        replaceGeneration += 1
        let thisGeneration = replaceGeneration
        replaceTask = Task { [weak self] in
            guard let self else { return }
            let results = await performReplace(
                root,
                plans,
                { @MainActor path in hasUnsaved(root.appendingPathComponent(path)) },
                { @MainActor [weak self] _ in
                    guard let self, replaceGeneration == thisGeneration else { return }
                    replaceCompleted += 1
                }
            )
            // Notified even when the run was superseded: the files are already rewritten on disk.
            for result in results {
                if case .replaced = result.outcome {
                    fileWasRewritten(root.appendingPathComponent(result.relativePath))
                }
            }
            guard replaceGeneration == thisGeneration else { return }
            replaceSummary = Self.summarize(results)
            isReplacing = false
            replaceTask = nil
            scheduleSearch(debounced: false, keepingReplaceSummary: true)
        }
    }

    static func summarize(_ results: [ReplacementFileResult]) -> FolderReplaceSummary {
        var summary = FolderReplaceSummary(replacedMatches: 0, replacedFiles: 0, skipped: [])
        for result in results {
            if case let .replaced(count) = result.outcome {
                summary.replacedMatches += count
                summary.replacedFiles += 1
            } else {
                summary.skipped.append(result)
            }
        }
        return summary
    }

    func replacementDidChange() {
        previews = [:]
        previewGeneration += 1
        for path in expandedPaths {
            loadPreview(path: path)
        }
    }

    func resetReplaceReview(keepingSummary: Bool) {
        excludedPaths = []
        expandedPaths = []
        previews = [:]
        previewGeneration += 1
        isConfirmingReplace = false
        if !keepingSummary, !isReplacing {
            replaceSummary = nil
        }
    }

    private func loadPreview(path: String) {
        guard let root, let match = results.first(where: { $0.relativePath == path }) else { return }
        let plan = ReplacementPlan(match, replacementText: replacement)
        let thisGeneration = previewGeneration
        Task { [weak self] in
            guard let self else { return }
            let preview = await performPreview(root, plan)
            guard previewGeneration == thisGeneration, expandedPaths.contains(path) else { return }
            previews[path] = preview
        }
    }
}
