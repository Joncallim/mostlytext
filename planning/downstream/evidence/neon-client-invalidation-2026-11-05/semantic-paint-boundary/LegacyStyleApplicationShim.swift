// Baseline-only model of the three original native token-application loops.
// This does not execute a native style interface.
import Foundation
import OwnedStylingCore
extension TokenApplication {
    package func forEachTokenToApply(_ apply: (Token, NSRange) -> Void) {
        for token in tokens { apply(token, token.range) }
    }
}
