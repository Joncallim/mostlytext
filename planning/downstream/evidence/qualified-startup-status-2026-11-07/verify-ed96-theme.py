import hashlib,io,json,pathlib,re,subprocess,sys
repo=pathlib.Path('/Volumes/Fast SSD/CORTANA-GitHub/mostlytext')
root=pathlib.Path(__file__).parent;head=sys.argv[1];name=sys.argv[2];base='6667bc9c1cb74534eafc417d921c3a37c55628b0';common='MacDown2/Packages/MacDownKit/Tests/HighlightingTests/CurrentLineRoleBitmapTests.swift';rows=[]
for phase in ['baseline','candidate']:
 p=root/name/phase;r=json.loads((p/'receipt.json').read_text());assert r['baseline']==(phase=='baseline');h=base if phase=='baseline' else head
 requests={(head if phase=='baseline' and n==common else h)+':'+n for n in r['source_sha256']}
 requests|={head+':MacDown2/Packages/MacDownKit/'+n for n in r['copied_test_sha256']}
 requests|={h+':MacDown2/Packages/MacDownKit/Package.resolved',head+':MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorGutterView.swift'}
 requests=sorted(requests);stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],input=('\n'.join(requests)+'\n').encode(),cwd=repo));blobs={}
 for n in requests:
  header=stream.readline().split();assert header[1]==b'blob',n;raw=stream.read(int(header[2]));assert stream.read(1)==b'\n';blobs[n]=raw
 for n,digest in r['source_sha256'].items():assert hashlib.sha256(blobs[(head if phase=='baseline' and n==common else h)+':'+n]).hexdigest()==digest,n
 for n,digest in r['copied_test_sha256'].items():assert hashlib.sha256(blobs[head+':MacDown2/Packages/MacDownKit/'+n]).hexdigest()==digest,n
 assert r['pins']==json.loads(blobs[h+':MacDown2/Packages/MacDownKit/Package.resolved'])['pins']
 actual='/Users/runner/work/mostlytext/mostlytext/MacDown2/Packages/MacDownKit' if phase=='candidate' else '/Users/runner/work/_temp/current-line-theme/baseline-checkout/MacDown2/Packages/MacDownKit'
 groups={'HighlightingTests':['Highlighting']} if phase=='baseline' else {'EditorCoreTests':['EditorCore','JSONSupport'],'HighlightingTests':['Highlighting'],'ThemesTests':['Themes']}
 targets=[]
 for group,products in groups.items():
  deps=', '.join('.product(name: '+json.dumps(product)+', package: "MacDownKit")' for product in products)
  targets.append('.testTarget(name: '+json.dumps(group)+', dependencies: ['+deps+'])')
 manifest='// swift-tools-version: 6.2\nimport PackageDescription\n'+'let package = Package(name: "CurrentLineThemeProbe", platforms: [.macOS(.v26)], dependencies: [.package(path: '+json.dumps(actual)+')], targets: [\n'+',\n'.join(targets)+'\n])\n'
 assert hashlib.sha256(manifest.encode()).hexdigest()==r['probe_manifest_sha256']
 log=(p/'probe.log').read_text();status=json.loads((p/'status.json').read_text());assert status['returncode']==(1 if phase=='baseline' else 0)
 assert re.search(r'Test run with 2 tests in 1 suite failed .* with 2 issues' if phase=='baseline' else r'Test run with 1087 tests in 145 suites passed',log)
 if phase=='candidate':
  assert 'Test denseInlineEditsKeepFreshCapturesAndPreviouslyRetainedSnapshots() passed' in log
  assert 'HIGHLIGHT_PHASE sourceUTF8=1000008 setup=' in log
  orientation=json.loads((root/name/'orientation-results.json').read_text());original=blobs[head+':MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorGutterView.swift'];needle=b'cgContext.textMatrix = Self.coreTextMatrix(forFlippedView: isFlipped)';assert original.count(needle)==1
  mutant=original.replace(needle,b'cgContext.textMatrix = .identity')
  assert orientation[0]['returncode']==1 and orientation[0]['source_sha256']==hashlib.sha256(mutant).hexdigest()
  assert orientation[1]['returncode']==0 and orientation[1]['source_sha256']==hashlib.sha256(original).hexdigest()
  assert orientation[0]['host_sha256']!=orientation[1]['host_sha256']
  for phase_name,expected in [('orientation-mutant','failed'),('orientation-restored','passed')]:
   t=(root/name/(phase_name+'.log')).read_text();assert re.search(r'Test run with 1 test in 1 suite '+expected,t)
 rows.append({'artifact':name,'phase':phase,'source_head':head,'checkout':r['checkout'],'verified_source_hashes':len(r['source_sha256']),'verified_copied_tests':len(r['copied_test_sha256']),'manifest_verified':True,'verified_pins':len(r['pins']),'results':[line for line in log.splitlines() if 'Test run with' in line or 'CURRENT-LINE-PHASE' in line]})
(root/(name+'-independently-verified.json')).write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(rows,indent=2))
