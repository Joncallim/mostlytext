import Foundation
import LocalResourceAccess

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

    private let resourceAccess: ExportResourceAccess?
    private let cancellation: ResourceCancellation
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
        resourceAccess: ExportResourceAccess?,
        cancellation: ResourceCancellation = ResourceCancellation(),
        unresolvedIsFatal: Bool,
        budget: ExportResourceBudget = .standard,
        assetsDirectoryName: String = ExportHTMLWriter.defaultAssetsDirectoryName
    ) {
        self.resourceAccess = resourceAccess
        self.cancellation = cancellation
        self.unresolvedIsFatal = unresolvedIsFatal
        self.budget = budget
        self.assetsDirectoryName = assetsDirectoryName
    }

    /// Decides how an authored URL should be rendered. `isImage` distinguishes a
    /// rendering resource (embed/pack) from a navigation link (policy only).
    func disposition(for url: String, isImage: Bool) throws -> URLDisposition {
        guard !cancellation.isCancelled else { throw CancellationError() }
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

        return try packageLocalResource(referencedBy: url)
    }

    func packagedIdentity(for reference: String) -> ExportResourceIdentity? {
        resourcesByReference[reference]?.identity
    }

    // MARK: - Local resources

    private func packageLocalResource(referencedBy url: String) throws -> URLDisposition {
        guard let resourceAccess else {
            return handleUnresolved(
                url: url,
                reason: String(localized: "no resource directory was admitted for this export", bundle: .module)
            )
        }
        let snapshot: ResourceSnapshot
        do {
            let reference = try ResourceReference.parse(url)
            // One bounded candidate is read at a time. Only admitted distinct
            // identities enter the aggregate; a duplicate consumes no quota.
            snapshot = try ContainedResourceReader.read(
                reference, in: resourceAccess.directory,
                maxBytes: budget.maxSingleResourceBytes, cancellation: cancellation
            )
        } catch ResourceReadError.cancelled {
            throw CancellationError()
        } catch ResourceReadError.oversized {
            return handleUnresolved(url: url, reason: singleLimitReason)
        } catch ResourceReadError.denied {
            return handleUnresolved(url: url, reason: "resource is outside the document's folder")
        } catch ResourceReadError.invalidReference {
            return handleUnresolved(url: url, reason: "reference is not a usable file path")
        } catch {
            return handleUnresolved(
                url: url,
                reason: String(localized: "resource could not be read through its admitted directory", bundle: .module)
            )
        }
        guard !cancellation.isCancelled else { throw CancellationError() }
        // Use the resolved leaf, not an alias such as image.png -> private.txt.
        let mimeType = ExportMIMEType.mimeType(forFileExtension: (snapshot.name as NSString).pathExtension)
        guard mimeType.hasPrefix("image/") else {
            return handleUnresolved(url: url, reason: "\(snapshot.name) is not an image file")
        }
        let resource = ExportResource(
            identity: ExportResourceIdentity(bytes: snapshot.bytes, mimeType: mimeType), bytes: snapshot.bytes
        )
        if let rejection = admit(resource) {
            return handleUnresolved(url: url, reason: rejection)
        }
        resourcesByReference[url] = resource
        return .rewrite(companionReference(for: resource))
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
