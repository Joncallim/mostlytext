import Foundation

/// The single set of safety gates an export runs under.
///
/// These are safety gates, not product semantics: they exist so a pathological
/// document cannot make the app read an unbounded file into memory, base64 it,
/// and stall or exhaust the process. Export uses one `.standard` budget that
/// callers cannot change. Passive Quick Look uses a separate tighter derived
/// budget because its reply and process deadlines are smaller.
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
    /// The actual-path Release ramp reached 1.39 GiB app peak RSS near the
    /// former 256 MiB ceiling. Approximately 128 MiB outputs stayed below
    /// 1 GiB in the same cohort; keep the limit at that measured tier.
    static let maxFinalHTMLUTF8Bytes = 128 << 20
    /// Existing managed HTML receipts and PDF outputs may reach the former
    /// bound. Recovery must still authenticate them, and PDF publication uses
    /// its own output policy rather than the new HTML assembly limit.
    static let maxManagedOutputBytes = 256 << 20
    /// Bound private occurrence records before cmark allocates its HTML buffer.
    static let maxResourceURLSlots = 65536
    /// Bound actual input work independently of distinct packaged payload.
    /// Provisional; failed/non-image/duplicate reads consume this allowance too.
    static let maxResourceReadAttempts = 4096
    static let maxResourceReadBytes = 256 << 20

    static let standard = ExportResourceBudget(
        maxSourceUTF8Bytes: 32 << 20,
        maxResourceCount: 512,
        maxSingleResourceBytes: 32 << 20,
        maxAggregateResourceBytes: 128 << 20,
        maxDerivedFragmentCount: 4096,
        maxAggregateDerivedHTMLBytes: 32 << 20,
        maxPreparedHTMLUTF8Bytes: 128 << 20
    )

    /// Provisional until the installed worker's Release memory and latency
    /// measurements are complete. No external file resources are admitted.
    static let passiveQuickLook = ExportResourceBudget(
        maxSourceUTF8Bytes: 1 << 20,
        maxResourceCount: 0,
        maxSingleResourceBytes: 0,
        maxAggregateResourceBytes: 0,
        maxDerivedFragmentCount: 128,
        maxAggregateDerivedHTMLBytes: 4 << 20,
        maxPreparedHTMLUTF8Bytes: 6 << 20
    )

    /// A human-readable size, used in diagnostics and error prose.
    static func describe(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
