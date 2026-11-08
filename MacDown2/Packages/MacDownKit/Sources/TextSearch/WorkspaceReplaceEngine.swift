import FileCore
import Foundation

public struct ReplacementFileResult: Sendable, Equatable {
    public let relativePath: String
    public let outcome: ReplacementFileOutcome

    public init(relativePath: String, outcome: ReplacementFileOutcome) {
        self.relativePath = relativePath
        self.outcome = outcome
    }
}

/// Applies an accepted Replace in Folder (EPIC-22 issue #112, Slice 7c) and
/// builds the before/after preview the user reviews first.
///
/// Safety contract, per file: the file is re-read and its bytes must still
/// hash to the revision the user reviewed (offsets are only meaningful
/// against that exact content); the fresh snapshot's own revision is then
/// passed as `FileStore.write`'s `expectedRevision`, so a writer that wins
/// between this read and publication is detected by `FileStore`'s
/// conditional publication instead of being overwritten. The file's own
/// encoding and BOM are preserved, and a replacement the encoding cannot
/// represent losslessly skips the file rather than corrupting it. Symbolic
/// links (the file, or any directory between it and the root) are never
/// written through. Files the caller marks protected (open with unsaved
/// edits) are never touched. Every non-`.replaced` outcome leaves the file
/// byte-for-byte unchanged, and one file's failure never stops the rest.
public actor WorkspaceReplaceEngine {
    public static let previewLineLimit = 5
    static let previewRegionCharacterLimit = 1000
    static let previewContextBeforeMatch = 80

    struct TestSeams: Sendable {
        /// Runs after the fresh read/verification and before publication —
        /// the window in which an external writer can win.
        var beforeWrite: (@Sendable (URL) -> Void)?
        var beforeEachFile: (@Sendable () async -> Void)?
    }

    private let seams: TestSeams
    private let store = FileStore()

    public init() {
        seams = TestSeams()
    }

    init(seams: TestSeams) {
        self.seams = seams
    }

    /// Streams one result per plan, in order, `await`-ing `onResult` after
    /// each. A cancellation observed between files marks every remaining
    /// plan `.notAttempted`; a file already being published is finished, not
    /// abandoned half-written.
    public func replace(
        root: URL,
        plans: [ReplacementPlan],
        isProtected: @escaping @Sendable (String) async -> Bool = { _ in false },
        onResult: @escaping @Sendable (ReplacementFileResult) async -> Void = { _ in }
    ) async -> [ReplacementFileResult] {
        var results: [ReplacementFileResult] = []
        results.reserveCapacity(plans.count)
        for plan in plans {
            await seams.beforeEachFile?()
            let outcome = await outcome(for: plan, root: root, isProtected: isProtected)
            let result = ReplacementFileResult(relativePath: plan.relativePath, outcome: outcome)
            results.append(result)
            await onResult(result)
        }
        return results
    }

    /// Cancellation is checked again AFTER the awaited protection query: the
    /// run can be retired (root change) while that await is suspended, and the
    /// check before it would then let a write through for a root the user has
    /// already left (#183 F14).
    private func outcome(
        for plan: ReplacementPlan,
        root: URL,
        isProtected: @Sendable (String) async -> Bool
    ) async -> ReplacementFileOutcome {
        if Task.isCancelled {
            return .notAttempted
        }
        let protected = await isProtected(plan.relativePath)
        if Task.isCancelled {
            return .notAttempted
        }
        return protected ? .skippedOpenDocumentWithUnsavedChanges : await apply(
            plan,
            root: root,
            isProtected: isProtected
        )
    }

    public func preview(root: URL, plan: ReplacementPlan) -> ReplacementFilePreview {
        let snapshot: FileSnapshot
        switch verifiedSnapshot(for: plan, root: root) {
        case let .success(value): snapshot = value
        case let .failure(outcome):
            switch outcome {
            case .skippedSymbolicLink: return .symbolicLink
            case .skippedUnreadable, .failed: return .unreadable
            default: return .changedSinceSearch
            }
        }
        guard plan.applying(to: snapshot.text) != nil else { return .changedSinceSearch }
        return Self.previewLines(text: snapshot.text, plan: plan)
    }

    // MARK: - Apply

    private func apply(
        _ plan: ReplacementPlan,
        root: URL,
        isProtected: @Sendable (String) async -> Bool
    ) async -> ReplacementFileOutcome {
        let snapshot: FileSnapshot
        switch verifiedSnapshot(for: plan, root: root) {
        case let .success(value): snapshot = value
        case let .failure(outcome): return outcome
        }
        guard let updated = plan.applying(to: snapshot.text) else { return .skippedCannotRepresent }
        let count = plan.matches.count
        if updated.unicodeScalars.elementsEqual(snapshot.text.unicodeScalars) {
            return .replaced(count: count)
        }

        // The protection query above ran BEFORE this file was read and hashed; the user can have started editing the
        // open document since. Ask again immediately before publishing (the remaining window is the actor hop plus
        // the conditional write, which an open dirty document would see as an external change, never a silent loss).
        if let refusal = await refusalBeforeWrite(plan, isProtected: isProtected) {
            return refusal
        }
        let url = snapshot.revision.url
        seams.beforeWrite?(url)
        do {
            try store.write(
                updated,
                to: url,
                encoding: snapshot.encoding,
                bom: snapshot.bom,
                expectedRevision: snapshot.revision
            )
            return .replaced(count: count)
        } catch {
            return Self.outcome(forWriteError: error, url: url, updated: updated, count: count)
        }
    }

    private static func outcome(
        forWriteError error: FileStoreError,
        url: URL,
        updated: String,
        count: Int
    ) -> ReplacementFileOutcome {
        switch error {
        case .fileChangedDuringRead:
            // `FileStore.write` also reports this from its post-publication
            // read-back, after our bytes are already on disk.
            contentEquals(url, updated) ? .replaced(count: count) : .skippedChangedSinceSearch
        case .encodingDetectionFailed, .textNotRepresentable: .skippedCannotRepresent
        case .fileMissing, .permissionDenied, .notRegularFile: .skippedUnreadable
        case let .conditionalPublicationRecoveryRequired(recovery):
            .failed(String(localized:
                "An external change could not be restored; its bytes were kept at \(recovery.path)", bundle: .module))
        default: .failed(String(describing: error))
        }
    }

    /// The last-moment gate: protection re-queried, cancellation re-observed.
    private func refusalBeforeWrite(
        _ plan: ReplacementPlan,
        isProtected: @Sendable (String) async -> Bool
    ) async -> ReplacementFileOutcome? {
        if await isProtected(plan.relativePath) {
            return .skippedOpenDocumentWithUnsavedChanges
        }
        return Task.isCancelled ? .notAttempted : nil
    }

    private static func contentEquals(_ url: URL, _ text: String) -> Bool {
        guard let snapshot = try? FileStore().readSnapshot(from: url) else { return false }
        return snapshot.text.unicodeScalars.elementsEqual(text.unicodeScalars)
    }

    private enum VerifiedRead {
        case success(FileSnapshot)
        case failure(ReplacementFileOutcome)
    }

    private func verifiedSnapshot(for plan: ReplacementPlan, root: URL) -> VerifiedRead {
        // Split on the `/` BYTE, not the `Character`: a `/` followed by a combining mark is one `Character`, so the
        // path was
        // never split and a symlinked directory above such a file was never checked (writes went through the link).
        let components = plan.relativePath.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { return .failure(.failed(String(localized: "Invalid path", bundle: .module))) }

        var current = root
        for component in components {
            current.appendPathComponent(component)
            switch Self.symbolicLinkState(of: current) {
            case .link: return .failure(.skippedSymbolicLink)
            case .missing: return .failure(.skippedUnreadable)
            case .notLink: continue
            }
        }

        let snapshot: FileSnapshot
        do {
            snapshot = try store.readSnapshot(from: current)
        } catch {
            if case .fileChangedDuringRead = error {
                return .failure(.skippedChangedSinceSearch)
            }
            return .failure(.skippedUnreadable)
        }
        guard snapshot.revision.sha256 == plan.revision.sha256,
              snapshot.revision.fileSize == plan.revision.fileSize
        else { return .failure(.skippedChangedSinceSearch) }
        return .success(snapshot)
    }

    private enum LinkState { case link, notLink, missing }

    private static func symbolicLinkState(of url: URL) -> LinkState {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType
        else { return .missing }
        return type == .typeSymbolicLink ? .link : .notLink
    }

    // MARK: - Preview

    static func previewLines(text: String, plan: ReplacementPlan) -> ReplacementFilePreview {
        let source = text as NSString
        var regions: [(range: NSRange, matches: [SearchMatch])] = []
        for match in plan.matches {
            var start = 0
            var end = 0
            var contentsEnd = 0
            source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: match.range)
            let regionEnd = max(contentsEnd, NSMaxRange(match.range))
            if var last = regions.last, start <= NSMaxRange(last.range) {
                last.range = NSRange(
                    location: last.range.location,
                    length: max(NSMaxRange(last.range), regionEnd) - last.range.location
                )
                last.matches.append(match)
                regions[regions.count - 1] = last
            } else {
                regions.append((NSRange(location: start, length: regionEnd - start), [match]))
            }
        }

        var lines: [ReplacementPreviewLine] = []
        var lineNumber = 1
        var cursor = 0
        for region in regions.prefix(previewLineLimit) {
            while cursor < region.range.location {
                cursor = NSMaxRange(source.lineRange(for: NSRange(location: cursor, length: 0)))
                lineNumber += 1
            }
            lines.append(ReplacementPreviewLine(
                lineNumber: lineNumber,
                before: clipped(region, in: source, replacement: nil),
                after: clipped(region, in: source, replacement: plan.replacementText)
            ))
        }
        return .lines(lines, totalRegionCount: regions.count)
    }

    private static func clipped(
        _ region: (range: NSRange, matches: [SearchMatch]),
        in source: NSString,
        replacement: String?
    ) -> String {
        var window = region.range
        if window.length > previewRegionCharacterLimit, let first = region.matches.first {
            let start = max(window.location, first.range.location - previewContextBeforeMatch)
            let end = min(NSMaxRange(window), start + previewRegionCharacterLimit)
            window = NSRange(location: start, length: end - start)
        }
        var output = source.substring(with: window) as NSString
        if let replacement {
            for match in region.matches.reversed() {
                let local = NSRange(location: match.range.location - window.location, length: match.range.length)
                guard local.location >= 0, NSMaxRange(local) <= output.length else { continue }
                output = output.replacingCharacters(in: local, with: replacement) as NSString
            }
        }
        var result = output as String
        if window.location > region.range.location {
            result = "…" + result
        }
        if NSMaxRange(window) < NSMaxRange(region.range) {
            result += "…"
        }
        return result
    }
}
