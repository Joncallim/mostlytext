import Foundation

/// The example scripts "Add Example Scripts" installs into the user's
/// Commands folder (epic-14-implementation.md §17 Slice 6). Embedded as
/// string literals rather than bundled resource files — a script is a
/// handful of lines, and this sidesteps giving a plain-text/no-extension
/// resource a bundle build rule for no real benefit.
enum BundledExampleScripts {
    struct Script {
        let filename: String
        let contents: String
    }

    static let all: [Script] = [
        Script(
            filename: "uppercase_selection.sh",
            contents: """
            #!/bin/sh
            # MostlyText example text-filter command.
            # Uppercases stdin (the selection, or the whole document when
            # nothing is selected) and writes the result to stdout.
            cat | tr '[:lower:]' '[:upper:]'
            """
        ),
        Script(
            filename: "sort_lines.sh",
            contents: """
            #!/bin/sh
            # MostlyText example text-filter command.
            # Sorts stdin's lines alphabetically.
            cat | sort
            """
        ),
    ]

    /// The outcome of installing one script, distinguishing "already there"
    /// (expected, not a problem) from "a filesystem operation actually
    /// failed" — collapsing the two into one boolean is what let a
    /// permission/disk-full/etc. failure masquerade as "nothing to do"
    /// (Codex review finding, PR #56).
    struct InstallResult {
        let installedCount: Int
        let hadFailure: Bool
    }

    private enum ScriptOutcome {
        case installed
        case alreadyExists
        case failed
    }

    /// Writes every script in `all` into `directory`, executable, skipping
    /// any filename that already exists there — installing examples must
    /// never silently overwrite a user's own edited copy.
    static func install(into directory: URL) -> InstallResult {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return InstallResult(installedCount: 0, hadFailure: true)
            }
        }

        var installedCount = 0
        var hadFailure = false
        for script in all {
            switch createExclusively(script, in: directory) {
            case .installed: installedCount += 1
            case .alreadyExists: break
            case .failed: hadFailure = true
            }
        }
        return InstallResult(installedCount: installedCount, hadFailure: hadFailure)
    }

    /// Creates `script`'s file with exclusive-create semantics (`O_CREAT |
    /// O_EXCL`) so a file that appears at this path between an earlier
    /// existence check and the write can never be silently replaced — the
    /// "never overwrite" invariant this installer promises (post-review
    /// finding #17). The file counts as installed only once it has been
    /// written *and* made executable; a write or `chmod` failure removes
    /// the partial file rather than leaving a non-executable script
    /// occupying the name, which would make every future install skip it
    /// while discovery never shows it. `errno` is captured immediately
    /// after `open` fails, before any other call can clobber it.
    private static func createExclusively(_ script: Script, in directory: URL) -> ScriptOutcome {
        let path = directory.appendingPathComponent(script.filename).path
        let (descriptor, openErrno): (Int32, Int32) = path.withCString {
            let openDescriptor = open($0, O_CREAT | O_EXCL | O_WRONLY, 0o755)
            return (openDescriptor, errno)
        }
        guard descriptor >= 0 else {
            return openErrno == EEXIST ? .alreadyExists : .failed
        }
        defer { close(descriptor) }

        let data = Data(script.contents.utf8)
        let wrote = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return true }
            return write(descriptor, base, buffer.count) == buffer.count
        }
        guard wrote, fchmod(descriptor, 0o755) == 0 else {
            try? FileManager.default.removeItem(atPath: path)
            return .failed
        }
        return .installed
    }
}
