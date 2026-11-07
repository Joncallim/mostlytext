import Foundation
import Darwin
@main struct OwnedJournalPathConsole {
 static func main() throws {
  let original = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
   .appendingPathComponent("mostlytext-path-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: original) }
  var template = Array("/private/tmp/mostlytext-path-XXXXXX".utf8CString)
  let physical = try template.withUnsafeMutableBufferPointer { buffer -> URL in
   guard let start = buffer.baseAddress, let path = mkdtemp(start) else { throw LegacyMigrationFailure.unavailable(errno) }
   return URL(fileURLWithPath: String(cString: path), isDirectory: true)
  }
  defer { try? FileManager.default.removeItem(at: physical) }
  guard let originalPhysicalPath = realpath(original.path, nil) else { throw LegacyMigrationFailure.unavailable(errno) }
  let canonicalOriginal = URL(fileURLWithPath: String(cString: originalPhysicalPath), isDirectory: true)
  free(originalPhysicalPath)
  var results: [[String: Any]] = []
  for (label, root) in [("original-foundation-temp", original),
                        ("same-directory-posix-physical", canonicalOriginal),
                        ("existing-private-mkdtemp", physical)] {
   let resolved = realpath(root.path, nil)
   let spelling = resolved.map { String(cString: $0) }
   if let resolved { free(resolved) }
   var row: [String: Any] = ["case": label, "root": root.path, "physical": spelling ?? "unavailable"]
   do {
    let journal = try MigrationJournalDirectory(url: root.appendingPathComponent("journal", isDirectory: true))
    defer { journal.close() }
    row["empty_read"] = try journal.read("plan.json") == nil
    row["admitted"] = true
   } catch {
    row["admitted"] = false
    row["error"] = String(reflecting: error)
   }
   results.append(row)
  }
  print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
 }
}
