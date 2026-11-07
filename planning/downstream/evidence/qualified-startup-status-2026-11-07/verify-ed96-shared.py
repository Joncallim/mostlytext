import hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='ed96eb6421d8094d672a546f0d1afa5f73d085d4';checkout='20015952d457fd06eb29599035f918493049e792';git=lambda *a:subprocess.check_output(['git',*a],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest()
paths=['MacDown2','.github/scripts/verify-shared-app-probe.py','.github/workflows/shared-math-app-integration.yml','.github/scripts/run-owned-app-tests.py','.github/scripts/test-run-owned-app-tests.py'];expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines());requests=[head+':'+p for p in sorted(expected)];stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for key in requests:
 h=stream.readline().split();assert h[1]==b'blob';raw=stream.read(int(h[2]));assert stream.read(1)==b'\n';blobs[key.split(':',1)[1]]=raw
assert git('show','-s','--format=%P',checkout).decode().split()==['6b49777d0f36c3d7a23cd0089e0823da1986660a',head]
assert git('rev-parse',head+'^{tree}')==git('rev-parse',checkout+'^{tree}')
suites=['SharedMathActivationTests','MathPreviewLiveSourceTests','MathPreviewNavigationTests','MathPreviewRecoveryTests','HeadingPreviewSessionTests','HeadingPreviewNavigationTests','HeadingPreviewAppTests','HeadingExportActivationTests','EditorStatusBarThemeTests'];rows=[]
for configuration in ['Debug','Release']:
 a=root/'ed96-shared-artifact'/('shared-math-app-tests-'+configuration);d=json.loads((a/'receipt.json').read_text());identity=json.loads((a/'diagnostics/identity.json').read_text());status=json.loads((a/'diagnostics/status.json').read_text());log=(a/'probe.log').read_text()
 assert d['checkout']==identity['checkout']==checkout and d['configuration']==configuration and d['testability'] is True and d['additional_compilation_condition']=='RELEASE_PREVIEW_PROBE'
 assert set(d['source_sha256'])==expected
 for p,h in d['source_sha256'].items():assert sha(blobs[p])==h,p
 assert d['pins']==json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins'] and len(d['pins'])==24
 assert status['returncode']==0 and not status['timed_out'] and not status['cancelled'] and not status['app_cleanup_requested'] and 0<status['elapsed_seconds']<600
 assert 'Test run with 29 tests in 9 suites passed' in log and 'recorded an issue' not in log and 'Restarting after unexpected' not in log
 for suite in suites:assert re.search('Suite '+suite+r' passed',log)
 assert 'TOC-PHASE configuration='+configuration in log
 cmd=identity['command'];assert cmd[0]=='xcodebuild' and '-configuration' in cmd and cmd[cmd.index('-configuration')+1]==configuration and 'ENABLE_TESTABILITY=YES' in cmd and 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) RELEASE_PREVIEW_PROBE' in cmd and '-onlyUsePackageVersionsFromResolvedFile' in cmd and '-parallel-testing-enabled' in cmd and cmd[cmd.index('-parallel-testing-enabled')+1]=='NO'
 for suite in suites:assert '-only-testing:MacDown2Tests/'+suite in cmd
 assert identity['app'].endswith('/'+configuration+'/MacDown2.app/Contents/MacOS/MacDown2') and re.fullmatch('[0-9a-f]{64}',identity['app_sha256'])
 colors=re.findall(r'Status theme=([^ ]+) space=sRGB[^\n]*',log);assert len(colors)==8 and len(set(colors))==8
 rows.append({'configuration':configuration,'source_inputs_verified':len(expected),'pins_verified':24,'actual_functions':29,'actual_suites':9,'actual_all_eight_status_theme_ids':colors,'owned':status,'actual_recorded_executable_sha256_not_downloaded':identity['app_sha256'],'actual_production_toc_phase_observed':True})
proof={'head':head,'checkout':checkout,'rows':rows,'scope':'Both actual testable app configurations genuinely execute all29functions/9suites including real status paint across8themes, production math/heading/native/export controls. Full canonical source/pins/command/executable records independently verified. Not rootapp binary download, public wholecritical/VoiceOver/protected owner/final signed-artifact acceptance.'};(root/'ed96-shared-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print(proof)
