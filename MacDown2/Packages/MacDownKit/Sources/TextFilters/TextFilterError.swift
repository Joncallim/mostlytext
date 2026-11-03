import Foundation

/// Every way a text-filter command can fail without corrupting the
/// document (epic-14-implementation.md §9). Every case is reachable only
/// *before* any editor mutation is attempted — the caller applies the
/// command's output only after `TextFilterRunner.run` returns
/// successfully, never incrementally.
public enum TextFilterError: Error, LocalizedError, Sendable, Equatable {
    /// The process could not be started at all (missing file, not
    /// executable, or another `Process.run()` failure). `underlying` is a
    /// `String`, not `Error`, so this case stays `Sendable`/`Equatable`.
    case launchFailed(underlying: String)
    case nonZeroExit(code: Int32, stderr: String)
    case timedOut
    /// The caller's own `Task` was cancelled while the command was
    /// running. Distinct from a real thrown `CancellationError` so this
    /// type stays a single, exhaustively-testable enum; callers that want
    /// "no alert on cancellation" (epic-14-implementation.md §9) match
    /// this case explicitly rather than relying on `catch is
    /// CancellationError`.
    case cancelled
    case outputTooLarge
    case outputNotDecodable
    /// The process group was terminated to force real EOF (e.g. a
    /// backgrounded descendant was holding a pipe open) but real EOF still
    /// could not be observed afterward. Second-adversarial-pass finding
    /// #1: this exists so an unexplained drain failure fails closed rather
    /// than ever being able to return a fabricated-EOF prefix as if it
    /// were complete, successful output.
    case outputIncomplete
    /// A forced shutdown (timeout/cancellation/oversized/incomplete
    /// output) could not be confirmed to have actually stopped every
    /// process in the filter's process group. Second-adversarial-pass
    /// finding #2: surfaced explicitly rather than silently claiming
    /// "stopped" when the confirmation step itself failed.
    case terminationUnconfirmed

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(underlying):
            String(localized: "Couldn't run the command: \(underlying)", bundle: .module)
        case let .nonZeroExit(code, stderr):
            if stderr.isEmpty {
                String(localized: "The command exited with status \(code).", bundle: .module)
            } else {
                String(localized: "The command exited with status \(code): \(stderr)", bundle: .module)
            }
        case .timedOut:
            String(localized: "The command took too long and was stopped.", bundle: .module)
        case .cancelled:
            String(localized: "The command was cancelled.", bundle: .module)
        case .outputTooLarge:
            String(localized: "The command produced more output than MostlyText will accept.", bundle: .module)
        case .outputNotDecodable:
            String(localized: "The command's output wasn't valid text.", bundle: .module)
        case .outputIncomplete:
            String(localized: "The command's output could not be fully read.", bundle: .module)
        case .terminationUnconfirmed:
            String(localized: "The command could not be confirmed stopped.", bundle: .module)
        }
    }
}
