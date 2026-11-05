import Foundation

public final class RangeInvalidationBuffer {
	public typealias Handler = (RangeTarget) -> Void

	private enum State: Hashable {
		case idle
		case buffering(RangeTarget, Int)
	}

	private var state = State.idle
	public var invalidationHandler: Handler = { _ in }

	public init() {
	}
}

extension RangeInvalidationBuffer {
	public func beginBuffering() {
		switch state {
		case .idle:
			self.state = .buffering(.set(IndexSet()), 1)
		case let .buffering(set, count):
			self.state = .buffering(set, count + 1)
		}
	}

	public func endBuffering() {
		switch state {
		case .idle:
			preconditionFailure()
		case let .buffering(set, 1):
			self.state = .idle
			// The handler may invalidate another range or open a new buffering scope.
			// Publish this batch only after leaving the old scope, so that work is not lost.
			invalidationHandler(set)
		case let .buffering(set, count):
			precondition(count > 1)
			self.state = .buffering(set, count - 1)
		}
	}

	public func invalidate(_ target: RangeTarget) {
		switch state {
		case .idle:
			invalidationHandler(target)
		case let .buffering(existing, count):
			precondition(count > 0)

			self.state = .buffering(existing.union(target), count)
		}
	}
}
