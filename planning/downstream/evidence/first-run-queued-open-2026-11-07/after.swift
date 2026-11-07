import Darwin
import Foundation
@MainActor final class Admission {
 var shouldShowFirstRun = true
 var launchURLs: [URL] = []
 var launchFolderURL: URL?
 var startupOpenFiles: [String] = []
 func welcomes() -> Bool {
  let hasQueuedDocuments = !Self.regularDocumentURLs(startupOpenFiles).isEmpty
  if shouldShowFirstRun, launchURLs.isEmpty, launchFolderURL == nil, !hasQueuedDocuments { return true }
  return false
 }
     private static func regularDocumentURLs(_ filenames: [String]) -> [URL] {
        filenames
            .map { URL(fileURLWithPath: $0).resolvingFinalSymlink() }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
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
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true).resolvingSymlinksInPath()
  guard root.deletingLastPathComponent().path == "/Volumes/Fast SSD/CORTANA-Builds/first-run-queued-open-20261107",
   !FileManager.default.fileExists(atPath:root.path) else { throw Input.refused }
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
  let directory=root.appendingPathComponent("session-directory",isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
  let file=root.appendingPathComponent("file.md");try Data("fixture".utf8).write(to:file,options:.withoutOverwriting)
  let missing=root.appendingPathComponent("missing.md")
  let dangling=root.appendingPathComponent("dangling.md");try FileManager.default.createSymbolicLink(at:dangling,withDestinationURL:missing)
  let link=root.appendingPathComponent("linked.md");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
  let linkedDirectory=root.appendingPathComponent("linked-directory");try FileManager.default.createSymbolicLink(at:linkedDirectory,withDestinationURL:directory)
  let removed=root.appendingPathComponent("removed.md");try Data("removed".utf8).write(to:removed,options:.withoutOverwriting)
  var rows:[[String:Any]]=[]
  func check(_ name:String,_ paths:[String],expected:Bool,first:Bool=true,explicitFile:Bool=false,explicitFolder:Bool=false,remove:URL?=nil) throws {
   let admission=Admission();admission.startupOpenFiles=paths;admission.shouldShowFirstRun=first
   admission.launchURLs=explicitFile ? [file] : [];admission.launchFolderURL=explicitFolder ? directory : nil
   if let remove {try FileManager.default.removeItem(at:remove)}
   let actual=admission.welcomes()
   rows.append(["name":name,"raw_queue":admission.startupOpenFiles,"expected_raw_queue":paths,"actual_welcome":actual,"expected_welcome":expected,"passed":actual==expected && admission.startupOpenFiles==paths])
  }
  try check("empty",[],expected:true)
  try check("session-directory",[directory.path],expected:true)
  try check("missing",[missing.path],expected:true)
  try check("dangling",[dangling.path],expected:true)
  try check("mixed-invalid",[directory.path,missing.path],expected:true)
  try check("regular",[file.path],expected:false)
  try check("linked-regular",[link.path],expected:false)
  try check("removed-before-decision",[removed.path],expected:true,remove:removed)
  try check("returning-user",[],expected:false,first:false)
  try check("explicit-file",[],expected:false,explicitFile:true)
  try check("explicit-folder",[],expected:false,explicitFolder:true)
  try check("linked-directory",[linkedDirectory.path],expected:true)
  try check("returning-user-invalid",[directory.path],expected:false,first:false)
  try check("mixed-regular",[directory.path,file.path,missing.path],expected:false)
  let failures=rows.filter{$0["passed"] as? Bool == false}.count
  let record:[String:Any]=["cases":rows,"total":rows.count,"failures":failures,"scope":"Literal actual condition/assignment/helper and URL extension; real private filesystem; no AppKit event delivery, actual historical queue or native acceptance"]
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]));FileHandle.standardOutput.write(Data([10]))
  exit(failures==0 ? 0:1)
 }
 enum Input:Error {case refused}
}
