import hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent
a=root/'ed96-public-focus-artifact/hosted-normal-public-focus'
d=json.loads((a/'receipt.json').read_text())
head='ed96eb6421d8094d672a546f0d1afa5f73d085d4'
repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext'
git=lambda *args:subprocess.check_output(['git','-C',repo,*args])
sha=lambda b:hashlib.sha256(b).hexdigest()
paths=['MacDown2','.github/hosted-public-focus','.github/scripts/prepare-hosted-public-focus.py','.github/scripts/run-hosted-public-focus.py','.github/scripts/test-hosted-focus-guard.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/native-cli-app-host.swift','.github/scripts/native_cli_endpoint_probe.py','.github/scripts/run-owned-app-tests.py','.github/workflows/hosted-public-focus.yml','.github/workflows/status-bar-layout.yml']
inputs=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines())
assert inputs==set(d['source_sha256'])
requests=[head+':'+p for p in sorted(inputs)]
stream=io.BytesIO(subprocess.check_output(['git','-C',repo,'cat-file','--batch'],input=('\n'.join(requests)+'\n').encode()))
blobs={}
for request in requests:
 h=stream.readline().split();assert h[1]==b'blob';raw=stream.read(int(h[2]));assert stream.read(1)==b'\n';p=request.split(':',1)[1];assert sha(raw)==d['source_sha256'][p],p;blobs[p]=raw
assert git('show','-s','--format=%P',d['checkout']).decode().split()==['6b49777d0f36c3d7a23cd0089e0823da1986660a',head]
assert git('rev-parse',head+'^{tree}')==git('rev-parse',d['checkout']+'^{tree}')
assert json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins']==d['pins'] and len(d['pins'])==24
for path,h in d['generated_sha256'].items():assert sha((a/'fixture'/path).read_bytes())==h,path
fixture={p.removeprefix('.github/hosted-public-focus/'):raw for p,raw in blobs.items() if p.startswith('.github/hosted-public-focus/')}
for path,raw in fixture.items():assert sha(raw)==d['generated_sha256'][path],path
assert set(d['generated_sha256'])==set(fixture)|{'Driver/HostedFocusInputs.swift','HostedPublicFocus.xcodeproj/project.pbxproj','HostedPublicFocus.xcodeproj/project.xcworkspace/contents.xcworkspacedata','HostedPublicFocus.xcodeproj/xcshareddata/xcschemes/HostedPublicFocus.xcscheme'}
original=git('show','6301b0fb914c2846e23c6c418d8b0be17242e6d3:.github/hosted-public-focus/Driver/PublicFocusTests.swift')
assert original==blobs['.github/hosted-public-focus/Driver/PublicFocusTests.swift'],'Every original failed journey assertion remains unchanged'
assert (a/'documents/focus-42343094444.md').read_bytes()==b'- item'
assert d['source_file_sha256']==sha(b'- item')
assert d['passed'] and not d['errors'] and not d.get('cleanup_errors')
assert d['criteria']=={'benign_control':True,'file_open_acknowledged':True,'public_focus_bold_undo':True,'unchanged_product_and_source':True,'normal_identity_bound_quit':True}
assert set(d['ui_results'])=={'positive','focus'}
for label,method in [('positive','testBenignInputControl'),('focus','testNormalPublicFocusBoldAndUndo')]:
 row=d['ui_results'][label];summary=json.loads((a/(label+'-summary.json')).read_text());owned=json.loads((a/(label+'-owned/status.json')).read_text())
 assert row['summary']==summary and row['owned']==owned
 for k,v in {'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}.items():assert summary[k]==v
 assert owned['returncode']==0 and owned['timed_out'] is False and owned['cancelled'] is False and owned['app_cleanup_requested']==[]
 assert 0<owned['elapsed_seconds']<600
 assert row['selected']=='HostedFocusDriverTests/PublicFocusTests/'+method
 assert re.search(r"Test Case '-\[HostedFocusDriverTests.PublicFocusTests "+method+r"\]' passed",(a/(label+'.log')).read_text())
assert json.loads((root/'ed96-focus-xcresult-summary.json').read_text())==d['ui_results']['focus']['summary']
commands={c['label']:c for c in d['commands']}
for label in ['source-and-build-verification-before','positive','actual-gui-metadata','app-launch','public-file-open','focus','app-inspect','source-and-build-verification-after','app-terminate']:assert commands[label]['returncode']==0,label
apps=d['applications'];assert [r['operation'] for r in apps]==['launch','inspect','terminate']
assert len({r['pid'] for r in apps})==len({r['birth'] for r in apps})==len({r['executable'] for r in apps})==1 and apps[-1]['terminated'] is True
for label in ['app-inspect','app-terminate']:
 assert commands[label]['command'][-2:]==[str(apps[0]['pid']),str(apps[0]['birth'])]
peer=d['live_endpoint'];assert peer['ready'] and peer['pid']==apps[0]['pid'] and peer['application_frames_sent']==0
assert peer['attempts'][-1]['peer_pid']==apps[0]['pid'] and peer['attempts'][-1]['peer_uid']==501 and peer['attempts'][-1]['mode']=='0o600'
facts=d['actual_gui'];assert facts['on_console'] and facts['login_done'] and facts['uid']==501 and facts['screen_lock_field'] is not True and facts['keyboard_input_source']=='com.apple.keylayout.US' and facts['screens']
assert d['built']['info']['CFBundleIdentifier']=='app.mostlytext.MostlyText'
generated=(a/'fixture/Driver/HostedFocusInputs.swift').read_text()
for value in [d['built']['app'],d['built']['executable'],d['built']['app_sha256'],'focus-42343094444.md',str(pathlib.PurePosixPath(d['source_file']).parent)]:assert json.dumps(value) in generated
proof={'head':head,'checkout':d['checkout'],'source_tree':git('rev-parse',head+'^{tree}').decode().strip(),'all_source_inputs_verified':len(inputs),'all_pins_verified':24,'all_generated_copied_files_downloaded_hash_verified':len(d['generated_sha256']),'original_failed_journey_source_byte_unchanged':True,'actual_positive_and_public_focus_tests_passed':2,'failures_skips_expected_failures':0,'criteria':d['criteria'],'positive_owned':d['ui_results']['positive']['owned'],'focus_owned':d['ui_results']['focus']['owned'],'actual_gui':facts,'actual_same_pid_birth_and_normal_quit':True,'unchanged_source_file_bytes':True,'recorded_build':d['built'],'scope':'Actual normal Release public UI: real folder selection, sidebar/Find/editor focus, fresh Bold eligibility, real Bold mutation and Undo. No root test flags/injection. Different disposable hosted machine, not protected CORTANA/original named UITest/full critical suite/performance or exact signed artifact. Binary digests are actual before/after verified hosted records, not downloaded binaries.'}
(root/'ed96-focus-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n')
print({k:v for k,v in proof.items() if not isinstance(v,dict)})
