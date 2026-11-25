import FileCore
import Foundation

public enum FileTreeOperationError: Error, Sendable, Equatable, LocalizedError {
    case nameEmpty
    case nameContainsPathSeparator
    case nameReserved(String)
    case nameExists(String)
    case sourceMissing
    case destinationNotDirectory
    case outsideCurrentRoot
    case staleOperation
    case moveIntoOwnSubtree
    case posix(Int32)
    case underlying(String)

    public var errorDescription: String? {
        message(locale: .current)
    }

    // One case per public error remains deliberate so no refusal loses its copy.
    // swiftlint:disable cyclomatic_complexity
    /// The sidebar presents this through `Text(verbatim:)`; resolve catalog
    /// copy for that view's locale while retaining authored underlying detail.
    public func message(locale: Locale, bundle: Bundle? = nil) -> String {
        let bundle = bundle ?? .module
        return switch self {
        case .nameEmpty: String(localized: "A name is required.", bundle: bundle, locale: locale)
        case .nameContainsPathSeparator: String(
                localized: "Names cannot contain / or :.",
                bundle: bundle,
                locale: locale
            )
        case let .nameReserved(name): String(
                localized: "\"\(name)\" is not a valid name.",
                bundle: bundle,
                locale: locale
            )
        case let .nameExists(name): String(localized: "\"\(name)\" already exists.", bundle: bundle, locale: locale)
        case .sourceMissing: String(localized: "The item no longer exists.", bundle: bundle, locale: locale)
        case .destinationNotDirectory: String(
                localized: "The destination is not a folder.",
                bundle: bundle,
                locale: locale
            )
        case .outsideCurrentRoot: String(
                localized: "The destination is outside the open folder.",
                bundle: bundle,
                locale: locale
            )
        case .staleOperation: String(
                localized: "The folder changed before the operation could start.",
                bundle: bundle,
                locale: locale
            )
        case .moveIntoOwnSubtree: String(
                localized: "A folder cannot be moved into itself.",
                bundle: bundle,
                locale: locale
            )
        case let .posix(code): String(
                localized: "Folder operation failed (POSIX error \(code)).",
                bundle: bundle,
                locale: locale
            )
        case let .underlying(message): message
        }
    }
    // swiftlint:enable cyclomatic_complexity
}

/// A caller captures this synchronously, before scheduling a CRUD task. Its
/// generation makes an A → B → A root replacement distinct from the original A.
public struct FileTreeOperationContext: Sendable, Equatable {
    let root: URL?
    let generation: UInt
}

public struct FileTreeOperationResult: Sendable, Equatable {
    public let url: URL
    public let isCurrent: Bool

    public init(url: URL, isCurrent: Bool) {
        self.url = url
        self.isCurrent = isCurrent
    }
}

public enum FileTreeNaming {
    public static func uniqueName(base: String, extension ext: String, existing: Set<String>) -> String {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let folded = Set(existing.map(foldedName))
        var index = 1
        while true {
            let name = index == 1 ? "\(base)\(suffix)" : "\(base) \(index)\(suffix)"
            if !folded.contains(foldedName(name)) {
                return name
            }
            index += 1
        }
    }

    private static func foldedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    /// Two-part extensions where the compressed suffix belongs with `.tar`: `archive.tar.gz` duplicates as
    /// `archive copy.tar.gz` (as Finder does), not `archive.tar copy.gz`.
    private static let compressedTarSuffixes: Set<String> = ["gz", "bz2", "xz", "zst", "lz", "lzma", "z"]

    public static func duplicateName(of name: String, existing: Set<String>) -> String {
        let copy = safeLocalizedNameFragment(
            String(localized: "copy", bundle: .module,
                   comment: "Lowercase suffix used when duplicating a file or folder name"),
            fallback: "copy"
        )
        return duplicateName(of: name, existing: existing, copyWord: copy)
    }

    static func safeLocalizedNameFragment(_ value: String, fallback: String) -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.utf8.contains(0), !value.utf8.contains(0x2F), !value.utf8.contains(0x3A),
              value != ".", value != ".."
        else { return fallback }
        return value
    }

    static func duplicateName(of name: String, existing: Set<String>, copyWord: String) -> String {
        let url = URL(fileURLWithPath: name)
        var stem = url.deletingPathExtension().lastPathComponent
        var ext = url.pathExtension
        if compressedTarSuffixes.contains(ext.lowercased()),
           URL(fileURLWithPath: stem).pathExtension.lowercased() == "tar" {
            let inner = URL(fileURLWithPath: stem)
            stem = inner.deletingPathExtension().lastPathComponent
            ext = "\(inner.pathExtension).\(ext)"
        }
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let folded = Set(existing.map(foldedName))
        var index = 1
        while true {
            let candidate = index == 1 ? "\(stem) \(copyWord)\(suffix)" : "\(stem) \(copyWord) \(index)\(suffix)"
            if !folded.contains(foldedName(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    public static func validate(
        _ name: String,
        existing: Set<String>,
        currentName: String?,
        isExistingFileName: Bool = false
    ) -> FileTreeOperationError? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .nameEmpty }
        // A name TYPED for a new/renamed item may not contain a separator, but an existing file being moved or
        // copied already has its legal on-disk name (`Meeting 10:30.md` is valid on APFS), which must not be refused.
        guard isExistingFileName || (!name.utf8.contains(0x2F) && !name.utf8.contains(0x3A)) else {
            return .nameContainsPathSeparator
        }
        // `.` and `..` name the directory itself and its parent: they fail at the filesystem with an odd error.
        guard name != ".", name != ".." else { return .nameReserved(name) }
        let names = existing.filter { candidate in candidate != currentName }
        return names.contains { $0.caseInsensitiveCompare(name) == .orderedSame } ? .nameExists(name) : nil
    }
}

public enum FileTreeMoveValidation {
    /// Path-COMPONENT containment, not string prefix (D10). Part of the
    /// documented public API contract (`planning/epic-09-implementation.md`
    /// §4.2) even though the model's own `move()` uses the stronger,
    /// symlink-aware `FileTreeCopySafety.validateDirectoryCopy` internally —
    /// this lexical check is the one package clients are specified to call.
    public static func validate(source: URL, intoDirectory destination: URL) -> FileTreeOperationError? {
        let sourceComponents = source.standardizedFileURL.pathComponents
        let destinationComponents = destination.standardizedFileURL.pathComponents
        if destinationComponents.starts(with: sourceComponents) {
            return .moveIntoOwnSubtree
        }
        return nil
    }
}

public enum FileTreeCopySafety {
    public static func validateDirectoryCopy(
        source: URL,
        intoDirectory destination: URL
    ) throws -> FileTreeOperationError? {
        let sourceID = try identity(of: source)
        var ancestor = destination.resolvingSymlinksInPath().standardizedFileURL
        while true {
            if try identity(of: ancestor) == sourceID {
                return .moveIntoOwnSubtree
            }
            if ancestor.path == "/" {
                return nil
            }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return nil }
            ancestor = parent
        }
    }

    private static func identity(of url: URL) throws -> PhysicalFileIdentity.FileObjectID {
        guard let identity = PhysicalFileIdentity(url: url).fileObjectID else {
            throw POSIXError(.ENOENT)
        }
        return identity
    }
}
