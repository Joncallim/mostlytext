import hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent
a=root/'4b67-status-artifact/hosted-normal-status-layout'
d=json.loads((a/'receipt.json').read_text())
head='4b6717905aaabb4053f20589ec323905d86dcef6'
repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext'
git=lambda *args:subprocess.check_output(['git','-C',repo,*args])
sha=lambda b:hashlib.sha256(b).hexdigest()
paths=['MacDown2','.github/hosted-public-focus','.github/scripts/prepare-hosted-public-focus.py','.github/scripts/run-hosted-public-focus.py','.github/scripts/test-hosted-focus-guard.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/native-cli-app-host.swift','.github/scripts/native_cli_endpoint_probe.py','.github/scripts/run-owned-app-tests.py','.github/workflows/hosted-public-focus.yml','.github/workflows/status-bar-layout.yml','.github/workflows/hosted-license-notices.yml','.github/scripts/test-hosted-license-notices.py','LICENSE','compliance/generated/THIRD_PARTY_NOTICES.md']
inputs=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines())
assert inputs==set(d['source_sha256'])
requests=[head+':'+p for p in sorted(inputs)]
stream=io.BytesIO(subprocess.check_output(['git','-C',repo,'cat-file','--batch'],input=('\n'.join(requests)+'\n').encode()))
blobs={}
for request in requests:
 h=stream.readline().split();assert h[1]==b'blob';raw=stream.read(int(h[2]));assert stream.read(1)==b'\n';p=request.split(':',1)[1];assert sha(raw)==d['source_sha256'][p],p;blobs[p]=raw
assert git('show','-s','--format=%P',d['checkout']).decode().split()==['ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9',head]
assert git('merge-tree','--write-tree','ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9',head).decode().strip()==git('rev-parse',d['checkout']+'^{tree}').decode().strip()
for name,raw in blobs.items():assert git('show',d['checkout']+':'+name)==raw,name
assert json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins']==d['pins'] and len(d['pins'])==24
for path,h in d['generated_sha256'].items():assert sha((a/'fixture'/path).read_bytes())==h,path
fixture={p.removeprefix('.github/hosted-public-focus/'):raw for p,raw in blobs.items() if p.startswith('.github/hosted-public-focus/')}
for path,raw in fixture.items():assert sha(raw)==d['generated_sha256'][path],path
assert set(d['generated_sha256'])==set(fixture)|{'Driver/HostedFocusInputs.swift','HostedPublicFocus.xcodeproj/project.pbxproj','HostedPublicFocus.xcodeproj/project.xcworkspace/contents.xcworkspacedata','HostedPublicFocus.xcodeproj/xcshareddata/xcschemes/HostedPublicFocus.xcscheme'}
original=git('show','6301b0fb914c2846e23c6c418d8b0be17242e6d3:.github/hosted-public-focus/Driver/PublicFocusTests.swift')
assert original==blobs['.github/hosted-public-focus/Driver/PublicFocusTests.swift'],'Every original failed journey assertion remains unchanged'
assert d['built']['license_resource_sha256'] and all(row['sha256']==d['source_sha256'][source] for source,row in d['license_oracles'].items())
assert sorted(d['built']['license_resource_sha256'].values())==sorted(row['sha256'] for row in d['license_oracles'].values())
assert (a/'documents/focus-42359123035.md').read_bytes()==b'- item'
assert d['source_file_sha256']==sha(b'- item')
assert d['passed'] and not d['errors'] and not d.get('cleanup_errors')
assert d['criteria']=={'benign_control':True,'file_open_acknowledged':True,'public_focus_bold_undo':True,'unchanged_product_and_source':True,'normal_identity_bound_quit':True}
assert set(d['ui_results'])=={'positive','focus'}
for label,method in [('positive','testBenignInputControl'),('focus','testNormalStatusBarRemainsReadableAtNarrowAndWideWidths')]:
 row=d['ui_results'][label];summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/(label+'.xcresult'))]));owned=json.loads((a/(label+'-owned/status.json')).read_text())
 assert row['summary']==summary and row['owned']==owned
 for k,v in {'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}.items():assert summary[k]==v
 assert owned['returncode']==0 and owned['timed_out'] is False and owned['cancelled'] is False and owned['app_cleanup_requested']==[]
 assert 0<owned['elapsed_seconds']<600
 assert row['selected']=='HostedFocusDriverTests/PublicFocusTests/'+method
 assert re.search(r"Test Case '-\[HostedFocusDriverTests.PublicFocusTests "+method+r"\]' passed",(a/(label+'.log')).read_text())
assert json.loads((root/'4b67-status-focus-actual-summary.json').read_text())==d['ui_results']['focus']['summary']
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
for value in [d['built']['app'],d['built']['executable'],d['built']['app_sha256'],'focus-42359123035.md',str(pathlib.PurePosixPath(d['source_file']).parent)]:assert json.dumps(value) in generated
proof={'actual_tested_tree':git('rev-parse','b61451098b8b5c068e13b20853e55414cee9a036^{tree}').decode().strip(),'all_bound_source_inputs_equal_across_documentation_base':True,'head':head,'checkout':d['checkout'],'source_tree':git('rev-parse',head+'^{tree}').decode().strip(),'all_source_inputs_verified':len(inputs),'all_pins_verified':24,'all_generated_copied_files_downloaded_hash_verified':len(d['generated_sha256']),'original_failed_journey_source_byte_unchanged':True,'actual_positive_and_public_focus_tests_passed':2,'failures_skips_expected_failures':0,'criteria':d['criteria'],'positive_owned':d['ui_results']['positive']['owned'],'focus_owned':d['ui_results']['focus']['owned'],'actual_gui':facts,'actual_same_pid_birth_and_normal_quit':True,'unchanged_source_file_bytes':True,'recorded_build':d['built'],'scope':'Actual normal Release public UI: real folder selection, sidebar/Find/editor focus, fresh Bold eligibility, real Bold mutation and Undo. No root test flags/injection. Different disposable hosted machine, not protected CORTANA/original named UITest/full critical suite/performance or exact signed artifact. Binary digests are actual before/after verified hosted records, not downloaded binaries.'}
attachments=root/'4b67-status-actual-attachments';manifest=json.loads((attachments/'manifest.json').read_text());assert len(manifest)==1;rows=manifest[0]['attachments'];geometry={};rectangles={}
ids=['statusBarLineColumn','statusBarCount','statusBarSyntaxMode','statusBarEncoding','statusBarLineEnding','statusBarIndentation']
for label,height,width in [('Narrow',41,398),('Wide',24,796)]:
 row=next(x for x in rows if x['suggestedHumanReadableName'].startswith(label+' status layout actual frames'))
 frame=json.loads((attachments/row['exportedFileName']).read_text());geometry[label]=frame
 assert frame['editorStatusBar.height']==height and frame['editorStatusBar.width']==width
 tree_row=next(x for x in rows if x['suggestedHumanReadableName'].startswith(label+' status layout accessibility tree'))
 tree=(attachments/tree_row['exportedFileName']).read_text();found={}
 for identifier in ['editorStatusBar',*ids]:
  lines=[line for line in tree.splitlines() if "identifier: '"+identifier+"'" in line];assert len(lines)==1
  match=re.search(r"\{\{([\d.]+), ([\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}",lines[0]);assert match
  found[identifier]=list(map(float,match.groups()))
 bar=found['editorStatusBar']
 for identifier in ids:
  x,y,w,h=found[identifier];assert w==frame[identifier+'.width'] and h==frame[identifier+'.height'] and 0<h<=24
  assert bar[0]<=x and bar[1]<=y and x+w<=bar[0]+bar[2] and y+h<=bar[1]+bar[3],identifier
 assert "value: 6 characters, 1 word" in tree
 rectangles[label]=found
assert all(geometry['Narrow'][name+'.width']>=geometry['Wide'][name+'.width']-1 for name in ids)
assert d['selected_public_method']=='testNormalStatusBarRemainsReadableAtNarrowAndWideWidths'
proof.update(actual_selected_status_case=True,actual_narrow_and_wide_frames=geometry,actual_all_six_complete_item_rectangles_inside_status_bounds=rectangles,actual_english_singular_count_visible=True)
proof['scope']='Actual normal Release public full focus/Bold/Undo journey plus unchanged genuine-before-failure status regression. All6 complete fields fit inside the real narrow/wide bar bounds; actual English singular visible, samePID/birth/normalQuit/source verified. Not extreme-overflow/pseudo/RTL/VoiceOver/native-language/finalcritical/owner/signed-artifact acceptance.'
(root/'4b67-status-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n')
print({k:v for k,v in proof.items() if not isinstance(v,dict)})
