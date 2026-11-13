import Foundation

/// Publication authority for one mounted large-Markdown highlighter.
///
/// Increment this at the storage gate's actual character-edit callback, not
/// at `EditorView.Coordinator.textDidChange`: the gate runs first. An
/// asynchronous parse captures a ticket before it starts and may publish
/// only while that exact storage generation and owner lifetime still hold.
@MainActor
final class MarkdownParseAuthority {
    struct Ticket: Equatable, Sendable {
        fileprivate let lifetime: UUID
        fileprivate let generation: UInt64
    }

    private let lifetime = UUID()
    private var generation: UInt64 = 0
    private var isActive = true

    func ticket() -> Ticket? {
        guard isActive else { return nil }
        return Ticket(lifetime: lifetime, generation: generation)
    }

    func admits(_ ticket: Ticket) -> Bool {
        isActive && ticket.lifetime == lifetime && ticket.generation == generation
    }

    /// Call synchronously for every actual character edit, including edits
    /// with no matching pre-edit proposal (undo, composition or reload).
    func noteStorageEdit() {
        advance()
    }

    /// A theme, font or language change can make an otherwise current token
    /// set wrong even if source bytes did not change.
    func invalidatePresentation() {
        advance()
    }

    func tearDown() {
        isActive = false
        advance()
    }

    private func advance() {
        // Saturate rather than wrap and accidentally admit a very old ticket.
        if generation == UInt64.max {
            isActive = false
        } else {
            generation += 1
        }
    }
}
