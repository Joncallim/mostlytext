// Baseline-only test shim: the old buffer has no edit-notification hook.
// This no-op models that absence. It is not production or native execution.
import Foundation
import RangeState
extension RangeInvalidationBuffer {
    package func contentChanged(in range: NSRange, delta: Int) {}
}
