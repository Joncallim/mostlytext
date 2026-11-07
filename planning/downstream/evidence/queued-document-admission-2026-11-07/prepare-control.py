import hashlib,json,pathlib,re,subprocess,sys
repo=pathlib.Path(sys.argv[1]);label=sys.argv[2];root=pathlib.Path(__file__).parent
source=(repo/'MacDown2/MacDown2/AppDelegate.swift').read_text();url=(repo/'MacDown2/Packages/MacDownKit/Sources/FileCore/URL+ResolvingFinalSymlink.swift').read_text()
def block(signature):
 start=source.index(signature);brace=source.index('{',start);depth=0
 for token in re.finditer(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}]',source[brace:],re.S):
  v=token.group()
  if v=='{':depth+=1
  elif v=='}':
   depth-=1
   if depth==0:return source[start:brace+token.end()]
 raise ValueError('Unclosed actual source block')
method=block('    func application(_: NSApplication, openFiles filenames: [String])')
helper=block('    private static func regularDocumentURLs(') if '    private static func regularDocumentURLs(' in source else ''
lines=[l.strip() for l in source.splitlines() if 'hasPendingDocumentOpen = !' in l];assert len(lines)==1
pending=lines[0]
program='''import Darwin
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
    func decidePending() { PENDING_ASSIGNMENT }
ACTUAL_HELPER
ACTUAL_METHOD
}
'''.replace('PENDING_ASSIGNMENT',pending).replace('ACTUAL_HELPER',helper).replace('ACTUAL_METHOD',method)
# The exact production URL extension uses only Foundation and Darwin.
program += '\n'+url
program += '''
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
'''
(root/(label+'.swift')).write_text(program)
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
record={'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'app_delegate_sha256':sha(source),'exact_actual_handler_sha256':sha(method),'exact_actual_helper_sha256':sha(helper) if helper else None,'exact_actual_pending_assignment':pending,'actual_url_source_sha256':sha(url),'generated_program_sha256':sha(program),'scope':'Literal actual handler/helper/pending expression + complete exact Foundation/Darwin URL extension; only unreachable AppKit/coordinator types are stand-ins. No filesystem mock or real AppKit execution.'}
(root/(label+'-input.json')).write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
