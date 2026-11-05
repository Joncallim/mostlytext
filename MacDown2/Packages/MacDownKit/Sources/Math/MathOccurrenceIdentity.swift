import CryptoKit
import Foundation
import MathSyntax

/// IDs bind occurrences to immutable source and lifetime, never theme/cache state.
enum MathOccurrenceIdentity {
    static func make(span: MathSyntaxSpan, sourceSHA256: String) -> UUID {
        let style = span.style == .inline ? "i" : "d"
        let seed = "mostlytext.math.occurrence.v1\n" + span.sourceIdentity.rawValue.uuidString + ":" +
            sourceSHA256 + ":\(span.fullRange.lowerBound):\(span.fullRange.upperBound):" + style
        let bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
