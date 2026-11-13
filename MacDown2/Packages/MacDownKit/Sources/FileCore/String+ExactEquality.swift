import Foundation

public extension String {
    /// Scalar-for-scalar equality. Swift's `==` treats canonically equivalent
    /// strings (U+212B ANGSTROM SIGN and U+00C5, or a precomposed and a
    /// decomposed é) as equal, which is wrong wherever the exact authored text
    /// decides persistence, dirtiness or what to publish (#183 F02). Display
    /// and name comparisons should keep using `==`.
    func isExactlyEqual(to other: String) -> Bool {
        // NSString compares literal UTF-16 code units, with no canonical
        // equivalence. Swift strings contain only valid scalar sequences, so
        // equal UTF-16 units are exactly equal scalar sequences as well.
        // The UTF-8 view's element iterator is costly for NSString-backed
        // editor text: a 1 MiB same-source comparison can dominate a keystroke.
        (self as NSString).isEqual(to: other)
    }
}
