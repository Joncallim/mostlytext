import hashlib,json,pathlib,re,subprocess,sys
repo=pathlib.Path(sys.argv[1]);label=sys.argv[2];root=pathlib.Path(__file__).parent
source=(repo/'MacDown2/MacDown2/AppDelegate.swift').read_text()
url=(repo/'MacDown2/Packages/MacDownKit/Sources/FileCore/URL+ResolvingFinalSymlink.swift').read_text()
start=source.index('    private static func regularDocumentURLs(');brace=source.index('{',start);depth=0;helper=None
for token in re.finditer(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}]',source[brace:],re.S):
 if token.group()=='{':depth+=1
 elif token.group()=='}':
  depth-=1
  if depth==0:helper=source[start:brace+token.end()];break
assert helper
conditions=re.findall(r'if shouldShowFirstRun,.*?\{',source,re.S);assert len(conditions)==1
condition=conditions[0][:-1].strip()
assignments=[l.strip() for l in source.splitlines() if l.strip().startswith('let hasQueuedDocuments =')]
assert len(assignments)<=1
assignment='\n'.join(assignments)
program='''import Darwin
import Foundation
@MainActor final class Admission {
 var shouldShowFirstRun = true
 var launchURLs: [URL] = []
 var launchFolderURL: URL?
 var startupOpenFiles: [String] = []
 func welcomes() -> Bool {
  ACTUAL_ASSIGNMENT
  ACTUAL_CONDITION { return true }
  return false
 }
 ACTUAL_HELPER
}
'''.replace('ACTUAL_ASSIGNMENT',assignment).replace('ACTUAL_CONDITION',condition).replace('ACTUAL_HELPER',helper)+url
program+='''
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
'''
(root/(label+'.swift')).write_text(program)
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
record={'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'app_delegate_sha256':sha(source),'exact_actual_condition':condition,'exact_actual_assignment':assignment,'actual_helper_sha256':sha(helper),'actual_url_source_sha256':sha(url),'generated_program_sha256':sha(program),'scope':'Literal actual predicates/helper/URL extension; model fields are console inputs, real filesystem, no AppKit or owner data'}
(root/(label+'-input.json')).write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
