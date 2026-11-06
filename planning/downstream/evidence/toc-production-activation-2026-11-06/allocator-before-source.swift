import CryptoKit
import Foundation

/// Allocates reproducible fragment IDs for parsed Markdown headings. Authored
/// HTML IDs remain exact strings; callers must inventory them before allocation.
public struct HeadingAnchorAllocator: Sendable {
    public static let policyVersion = 1

    private var usedIDs: Set<Data>

    public init() {
        usedIDs = []
    }

    /// A sequence preserves canonically equivalent but DOM-distinct authored
    /// IDs. Callers must not collapse their inventory with Set<String> first.
    public init(reservedIDs: some Sequence<String>) {
        usedIDs = Set(reservedIDs.map { Data($0.utf8) })
    }

    public mutating func allocate(title: String) -> String {
        let base = Self.normalizedBase(title)
        var duplicate = 0
        while true {
            let candidate = Self.boundedID(base: base, duplicate: duplicate)
            if usedIDs.insert(Data(candidate.utf8)).inserted {
                return candidate
            }
            duplicate += 1
        }
    }

    private static func normalizedBase(_ title: String) -> String {
        let normalized = title.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        var result = ""
        var pendingSpace = false
        for scalar in normalized.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSpace = !result.isEmpty
                continue
            }
            let category = scalar.properties.generalCategory
            let admitted = switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter, .decimalNumber,
                 .letterNumber, .otherNumber, .nonspacingMark,
                 .spacingMark, .enclosingMark:
                true
            default:
                scalar == "_" || scalar == "-"
            }
            guard admitted else { continue }
            if pendingSpace {
                result.append("-")
                pendingSpace = false
            }
            result.unicodeScalars.append(scalar)
        }
        let base = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return base.isEmpty ? "section" : base
    }

    private static func boundedID(base: String, duplicate: Int) -> String {
        let suffix = duplicate == 0 ? "" : "-\(duplicate)"
        if base.utf8.count + suffix.utf8.count <= 256 {
            return base + suffix
        }
        let digest = SHA256.hash(data: Data(base.utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let ending = "-\(fingerprint)\(suffix)"
        let prefixBudget = max(0, 256 - ending.utf8.count)
        var prefix = ""
        var prefixBytes = 0
        for character in base {
            let characterBytes = String(character).utf8.count
            if prefixBytes + characterBytes > prefixBudget {
                break
            }
            prefix.append(character)
            prefixBytes += characterBytes
        }
        prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return prefix + ending
    }
}
