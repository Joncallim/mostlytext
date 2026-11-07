import Darwin
import Foundation
struct NSApplication {}
@MainActor final class UnreachableCoordinator {
    func settleLaunchRestoration() async { fatalError("Post-ready coordinator must not run") }
    func openDocument(at _: URL) async { fatalError("Post-ready coordinator must not run") }
}
@MainActor final class Admission {
    var normalLaunchReady = false
    var startupOpenFiles: [String] = []
    var hasPendingDocumentOpen = false
    let coordinator = UnreachableCoordinator()
    func decidePending() { hasPendingDocumentOpen = !startupOpenFiles.isEmpty }

    func application(_: NSApplication, openFiles filenames: [String]) {
        guard normalLaunchReady else {
            startupOpenFiles.append(contentsOf: filenames)
            return
        }
        // AppKit also routes bare launch-argument paths (such as the
        // `-sessionDir` value under UI testing) and folder drops through this
        // handler. Only regular files count as document opens; anything else
        // must not suppress the session restore.
        let fileURLs = filenames
            .map { URL(fileURLWithPath: $0).resolvingFinalSymlink() }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        guard !fileURLs.isEmpty else { return }
        hasPendingDocumentOpen = true
        Task { @MainActor in
            await coordinator.settleLaunchRestoration()
            for url in fileURLs {
                await coordinator.openDocument(at: url)
            }
        }
    }
}

import Darwin
import Foundation

public extension URL {
    /// `self`, with a symbolic link in the FINAL path component followed to the
    /// file it names (relative targets resolved against the link's directory).
    ///
    /// Documents are opened at the file a link points to: saving through
    /// `FileStore`'s replace-the-file publication would otherwise either refuse
    /// the link (`.notRegularFile`) or replace the link itself with a regular
    /// file. The link stays in place and the target's content is what is edited.
    /// A dangling link, a loop, or a non-link comes back unchanged. Only the last
    /// component is resolved — the path's directories keep their spelling.
    func resolvingFinalSymlink() -> URL {
        guard isFileURL else { return self }
        var current = standardizedFileURL
        for _ in 0 ..< 16 {
            var info = stat()
            guard lstat(current.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK,
                  let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)
            else { return current }
            let next = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : current.deletingLastPathComponent().appendingPathComponent(destination)
            current = next.standardizedFileURL
        }
        return standardizedFileURL // a loop: leave it for the open to refuse
    }
}

@main struct Control {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Input.refused }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).resolvingSymlinksInPath()
        guard root.deletingLastPathComponent().path == "/Volumes/Fast SSD/CORTANA-Builds/queued-document-admission-20261107",
              !FileManager.default.fileExists(atPath: root.path) else { throw Input.refused }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let directory = root.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = root.appendingPathComponent("file.md")
        try Data("private source control".utf8).write(to: file, options: .withoutOverwriting)
        let missing = root.appendingPathComponent("missing.md")
        let dangling = root.appendingPathComponent("dangling.md")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: missing)
        let link = root.appendingPathComponent("linked.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let removed = root.appendingPathComponent("removed.md")
        try Data("removed private control".utf8).write(to: removed, options: .withoutOverwriting)
        var rows: [[String: Any]] = []
        func check(_ name: String, _ paths: [String], expected: Bool, remove: URL? = nil) throws {
            let admission = Admission()
            admission.application(NSApplication(), openFiles: paths)
            if let remove { try FileManager.default.removeItem(at: remove) }
            admission.decidePending()
            rows.append(["name": name, "queued_raw": admission.startupOpenFiles, "expected_queue_raw": paths,
                         "pending": admission.hasPendingDocumentOpen, "expected_pending": expected,
                         "passed": admission.startupOpenFiles == paths && admission.hasPendingDocumentOpen == expected])
        }
        try check("directory", [directory.path], expected: false)
        try check("missing", [missing.path], expected: false)
        try check("dangling", [dangling.path], expected: false)
        try check("regular", [file.path], expected: true)
        try check("mixed", [directory.path, file.path, missing.path], expected: true)
        try check("empty", [], expected: false)
        try check("linked-regular", [link.path], expected: true)
        try check("removed-before-readiness", [removed.path], expected: false, remove: removed)
        let failures = rows.filter { $0["passed"] as? Bool == false }.count
        let record: [String: Any] = ["cases": rows, "total": rows.count, "failures": failures,
                                    "scope": "Exact production source fragments with readiness false, real private filesystem, unreachable UI stand-ins; not AppKit callback or native acceptance"]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]))
        FileHandle.standardOutput.write(Data([10]))
        exit(failures == 0 ? 0 : 1)
    }
    enum Input: Error { case refused }
}
