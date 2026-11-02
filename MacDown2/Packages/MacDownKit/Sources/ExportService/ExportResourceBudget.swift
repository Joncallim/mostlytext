import Foundation

/// The single set of safety gates an export runs under.
///
/// These are safety gates, not product semantics: they exist so a pathological
/// document cannot make the app read an unbounded file into memory, base64 it,
/// and stall or exhaust the process. There is exactly one budget — callers
/// cannot supply one, and there are no call-site literals; the composer applies
/// `.standard` and tests inject small values to exercise the boundaries.
struct ExportResourceBudget: Sendable, Equatable {
    /// Largest Markdown source accepted, in UTF-8 bytes.
    let maxSourceUTF8Bytes: Int
    /// Largest number of distinct resources one export may package.
    let maxResourceCount: Int
    /// Largest single resource, in bytes.
    let maxSingleResourceBytes: Int
    /// Largest total resource payload, in bytes.
    let maxAggregateResourceBytes: Int
    /// Largest number of derived contributions placed in one export.
    let maxDerivedFragmentCount: Int
    /// Largest total derived HTML payload, in UTF-8 bytes.
    let maxAggregateDerivedHTMLBytes: Int
    /// Largest composed HTML body, in UTF-8 bytes.
    let maxPreparedHTMLUTF8Bytes: Int

    /// Largest complete HTML document, including repeated data URIs and shell.
    /// Provisional safety ceiling; Release memory calibration remains required.
    static let maxFinalHTMLUTF8Bytes = 256 << 20

    static let standard = ExportResourceBudget(
        maxSourceUTF8Bytes: 32 << 20,
        maxResourceCount: 512,
        maxSingleResourceBytes: 32 << 20,
        maxAggregateResourceBytes: 128 << 20,
        maxDerivedFragmentCount: 4096,
        maxAggregateDerivedHTMLBytes: 32 << 20,
        maxPreparedHTMLUTF8Bytes: 128 << 20
    )

    /// A human-readable size, used in diagnostics and error prose.
    static func describe(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
