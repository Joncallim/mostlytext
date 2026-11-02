import Foundation

/// Resolves authored image references to local resources, applying the export
/// URL policy, the resource root containment rule and the export budget, and
/// packaging bytes into the content-addressed manifest.
///
/// This is a transient builder: it accumulates resources and diagnostics during
/// the single cmark tree walk, then the composer freezes it into an immutable
/// `ExportManifest`. It is deliberately a class (not Sendable) because it is a
/// scratch accumulator local to one composition pass.
final class ExportResourceResolver {
    /// Authored reference URL → resource. Deduplication is by resource identity,
    /// so two references to the same bytes share one resource entry.
    private var resourcesByReference: [String: ExportResource] = [:]
    /// References already reported on, unresolved or blanked. A document that
    /// uses one broken image twenty times has one problem, not twenty.
    private var reportedReferences: Set<String> = []
    private(set) var diagnostics: [ExportDiagnostic] = []

    private let documentDirectory: URL?
    /// The canonical resource root: the resolved parent directory of the saved
    /// document, with a trailing separator so prefix comparison cannot match a
    /// sibling directory whose name merely starts with the root's.
    private let resourceRootPrefix: String?
    /// When true, an unresolved or remote *rendering* resource (image) is a
    /// fatal condition; when false it is reported as a warning and left as
    /// authored. Applies to self-contained HTML and PDF.
    private let unresolvedIsFatal: Bool
    private let budget: ExportResourceBudget
    /// The per-document companion directory name every rewritten reference is
    /// placed under. Supplied by the composer (from the primary output URL) so
    /// two documents exported into the same folder never share one.
    private let assetsDirectoryName: String

    private var aggregateResourceBytes = 0
    private var packagedIdentities: Set<ExportResourceIdentity> = []

    init(
        documentDirectory: URL?,
        unresolvedIsFatal: Bool,
        budget: ExportResourceBudget = .standard,
        assetsDirectoryName: String = ExportHTMLWriter.defaultAssetsDirectoryName
    ) {
        self.documentDirectory = documentDirectory
        self.unresolvedIsFatal = unresolvedIsFatal
        self.budget = budget
        self.assetsDirectoryName = assetsDirectoryName
        if let documentDirectory {
            let root = documentDirectory.standardizedFileURL.resolvingSymlinksInPath().path
            resourceRootPrefix = root.hasSuffix("/") ? root : root + "/"
        } else {
            resourceRootPrefix = nil
        }
    }

    /// Decides how an authored URL should be rendered. `isImage` distinguishes a
    /// rendering resource (embed/pack) from a navigation link (policy only).
    func disposition(for url: String, isImage: Bool) -> URLDisposition {
        // Inline raster data is already self-contained: nothing to fetch, pack or blank.
        if isImage, ExportURLPolicy.isEmbeddedRasterImage(url) {
            return .keep
        }
        guard ExportURLPolicy.isSafe(url) else {
            // The reference is neutralised, so the reader must be told: an
            // emptied `href`/`src` is otherwise indistinguishable from a typo.
            return reportBlanked(url: url)
        }

        // Navigation links to local/remote destinations are left as authored;
        // they are not fetched, embedded, or rewritten.
        guard isImage else {
            return .keep
        }

        // A document that uses the same image twenty times reads and hashes it
        // once. Repeating that work is the most expensive thing an image-heavy
        // export could do, and it produces nothing new.
        if let cached = resourcesByReference[url] {
            return .rewrite(companionReference(for: cached))
        }
        if reportedReferences.contains(url) {
            return .keep
        }

        // No `data:` reaches here: inline raster images are kept above and every other
        // `data:` URL is blanked by `ExportURLPolicy`.
        switch ExportURLPolicy.scheme(of: url) {
        case "http", "https":
            // Remote rendering resources are never fetched (offline guarantee).
            return handleUnresolved(url: url, reason: "remote resource is not fetched during offline export")
        default:
            break
        }

        // Fragments (in-document anchors) are not resources.
        if url.hasPrefix("#") {
            return .keep
        }

        return packageLocalResource(referencedBy: url)
    }

    func packagedIdentity(for reference: String) -> ExportResourceIdentity? {
        resourcesByReference[reference]?.identity
    }

    // MARK: - Local resources

    private func packageLocalResource(referencedBy url: String) -> URLDisposition {
        guard let fileURL = containedFileURL(for: url) else {
            // `containedFileURL` has already recorded why.
            return .keep
        }

        // `fileURL` is already the fully symlink-resolved target (see
        // `containedFileURL`), so `.isRegularFileKey` reports on the real file
        // a symlink points to, not on the symlink itself — a symlink to a
        // regular file inside the root is accepted, a directory, device,
        // socket or FIFO is not, and only ordinary file bytes are ever handed
        // to `Data(contentsOf:)`.
        guard let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
              isRegularFile else {
            return handleUnresolved(url: url, reason: "resource is not a readable file at \(fileURL.lastPathComponent)")
        }

        // This path serves image references only. Anything else in the document's folder
        // (`![x](.env)`, `![x](notes.txt)`) must not be copied into, or embedded in, an export
        // that is then shared.
        guard ExportMIMEType.mimeType(forFileExtension: fileURL.pathExtension).hasPrefix("image/") else {
            return handleUnresolved(url: url, reason: "\(fileURL.lastPathComponent) is not an image file")
        }

        // Size is read from the file's metadata first, so an oversized file is
        // rejected without ever entering memory.
        if let declared = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           declared > budget.maxSingleResourceBytes {
            return handleUnresolved(url: url, reason: singleLimitReason)
        }
        guard let bytes = try? Data(contentsOf: fileURL) else {
            return handleUnresolved(url: url, reason: "resource could not be read at \(fileURL.lastPathComponent)")
        }
        guard bytes.count <= budget.maxSingleResourceBytes else {
            return handleUnresolved(url: url, reason: singleLimitReason)
        }

        let mimeType = ExportMIMEType.mimeType(forFileExtension: fileURL.pathExtension)
        let resource = ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: mimeType), bytes: bytes)
        if let rejection = admit(resource) {
            return handleUnresolved(url: url, reason: rejection)
        }

        resourcesByReference[url] = resource
        return .rewrite(companionReference(for: resource))
    }

    /// The file an authored reference points at, fully symlink-resolved, or
    /// `nil` (with a diagnostic recorded) when it cannot be resolved inside
    /// the document's own folder.
    ///
    /// The resolved URL — not the as-authored one — is what containment is
    /// checked against and what every later step (`isRegularFile`, size, the
    /// actual read) operates on, so there is exactly one notion of "the file"
    /// a reference names, not two that could disagree across a symlink hop.
    private func containedFileURL(for url: String) -> URL? {
        guard let documentDirectory, let resourceRootPrefix else {
            _ = handleUnresolved(url: url, reason: "untitled document has no directory to resolve resources from")
            return nil
        }
        guard let relativePath = filesystemPath(from: url) else {
            _ = handleUnresolved(url: url, reason: "reference is not a usable file path")
            return nil
        }

        let candidate = documentDirectory.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        // Root containment: the resource root is the document's own directory.
        // A reference that climbs out of it (`../../.ssh/id_rsa`), directly or
        // through a symlink hop, is never read, so an export can only ever
        // carry files from the document's folder.
        guard resolved.path.hasPrefix(resourceRootPrefix) else {
            _ = handleUnresolved(url: url, reason: "resource is outside the document's folder")
            return nil
        }
        return resolved
    }

    /// Admits a resource against the count and aggregate budgets, returning a
    /// rejection reason when it does not fit. Budgets count *distinct* resources,
    /// so a document that repeats one image is not charged for it twice.
    private func admit(_ resource: ExportResource) -> String? {
        guard !packagedIdentities.contains(resource.identity) else {
            return nil
        }
        guard packagedIdentities.count < budget.maxResourceCount else {
            return "the export already carries its \(budget.maxResourceCount)-resource limit"
        }
        let (total, overflowed) = aggregateResourceBytes.addingReportingOverflow(resource.bytes.count)
        guard !overflowed, total <= budget.maxAggregateResourceBytes else {
            return aggregateLimitReason
        }
        aggregateResourceBytes = total
        packagedIdentities.insert(resource.identity)
        return nil
    }

    // MARK: - Helpers

    private var singleLimitReason: String {
        let limit = ExportResourceBudget.describe(bytes: budget.maxSingleResourceBytes)
        return "resource is larger than the \(limit) per-file export limit"
    }

    private var aggregateLimitReason: String {
        let limit = ExportResourceBudget.describe(bytes: budget.maxAggregateResourceBytes)
        return "the export exceeds its \(limit) total resource limit"
    }

    private func companionReference(for resource: ExportResource) -> String {
        "\(ExportHTMLWriter.percentEncodedCompanionComponent(assetsDirectoryName))/\(resource.identity.fileName)"
    }

    /// The filesystem-relative path an authored reference points at: query and
    /// fragment removed, percent-encoding decoded.
    ///
    /// Decoding matters in practice — macOS filenames routinely contain spaces,
    /// and anything that writes a Markdown link for you emits `my%20image.png`.
    private func filesystemPath(from url: String) -> String? {
        let withoutFragment = url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
        let withoutQuery = (withoutFragment ?? "").split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first
        let path = String(withoutQuery ?? "")
        let decoded = path.removingPercentEncoding ?? path
        return decoded.isEmpty ? nil : decoded
    }

    /// Records that a dangerous authored scheme was emptied, once per URL.
    private func reportBlanked(url: String) -> URLDisposition {
        guard reportedReferences.insert(url).inserted else {
            return .blank
        }
        diagnostics.append(ExportDiagnostic(
            severity: .warning,
            message: "Removed the target of \"\(url)\": that URL scheme is not allowed in an exported document."
        ))
        return .blank
    }

    private func handleUnresolved(url: String, reason: String) -> URLDisposition {
        guard reportedReferences.insert(url).inserted else {
            return .keep
        }
        let message = "Unresolved resource \"\(url)\": \(reason)."
        diagnostics.append(ExportDiagnostic(severity: unresolvedIsFatal ? .error : .warning, message: message))
        return .keep
    }

    /// Freezes the accumulated resources into a stable manifest. Resources are
    /// deduplicated by identity and ordered deterministically by filename.
    func frozenManifest() -> ExportManifest {
        var byIdentity: [ExportResourceIdentity: ExportResource] = [:]
        byIdentity.reserveCapacity(resourcesByReference.count)
        for resource in resourcesByReference.values where byIdentity[resource.identity] == nil {
            byIdentity[resource.identity] = resource
        }
        let sorted = byIdentity.values.sorted { $0.identity.fileName < $1.identity.fileName }
        return ExportManifest(resources: sorted, referenceMap: resourcesByReference.mapValues { $0.identity.fileName })
    }
}
