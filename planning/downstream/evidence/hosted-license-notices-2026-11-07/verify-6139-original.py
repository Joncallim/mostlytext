import hashlib,io,json,pathlib,plistlib,re,subprocess
root=pathlib.Path(__file__).parent
a=root/'6139-original-focus-artifact/hosted-original-focus'
d=json.loads((a/'receipt.json').read_text())
head='6139bc613dd2bad61215a49336d7d4620975465f'
base='020ff640cc5658535eaea6c695629d00095c2bb7'
repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext'
git=lambda *args:subprocess.check_output(['git','-C',repo,*args])
sha=lambda b:hashlib.sha256(b).hexdigest()
paths=['MacDown2','.github/hosted-original-focus','.github/hosted-public-focus','.github/scripts/prepare-hosted-public-focus.py','.github/scripts/run-hosted-original-focus.py','.github/scripts/run-owned-app-tests.py','.github/scripts/test-hosted-focus-guard.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/check-native-ui-required-cases.py','.github/scripts/test-native-ui-required-cases.py','planning/downstream/native-ui-required-cases.json','.github/workflows/hosted-original-focus.yml']
expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines())
assert expected==set(d['source_sha256'])
requests=[head+':'+p for p in sorted(expected)]
stream=io.BytesIO(subprocess.check_output(['git','-C',repo,'cat-file','--batch'],input=('\n'.join(requests)+'\n').encode()))
blobs={}
for key in requests:
 h=stream.readline().split();assert h[1]==b'blob';raw=stream.read(int(h[2]));assert stream.read(1)==b'\n';p=key.split(':',1)[1];assert sha(raw)==d['source_sha256'][p],p;blobs[p]=raw
assert json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins']==d['pins'] and len(d['pins'])==24
assert git('show','-s','--format=%P',d['checkout']).decode().split()==[base,head]
tree=git('rev-parse',head+'^{tree}').decode().strip()
assert git('rev-parse',d['checkout']+'^{tree}').decode().strip()==git('merge-tree','--write-tree',base,head).decode().strip()
for name,raw in blobs.items():assert git('show',d['checkout']+':'+name)==raw,name
assert git('show',head+':MacDown2/MacDown2UITests/EditingAssistsUITests.swift')==git('show',base+':MacDown2/MacDown2UITests/EditingAssistsUITests.swift')
for p,h in d['generated_sha256'].items():assert sha((a/'fixture'/p).read_bytes())==h,p
for source,target in d['fixture_mapping'].items():assert sha(blobs[source])==d['generated_sha256'][target],source
assert d['passed'] is True and d['source_unchanged_after'] is True and d['errors']==[]
selected='MacDown2UITests/EditingAssistsUITests/testFormattingMenuTracksEditorSidebarFindAndEditorFocus'
assert d['selected_original']==selected
assert set(d['results'])=={'positive','original'}
for label in ['positive','original']:
 row=d['results'][label];status=json.loads((a/(label+'-owned/status.json')).read_text())
 assert status==row['owned'] and status['returncode']==0 and not status['timed_out'] and not status['cancelled'] and not status['app_cleanup_requested']
 for k,v in {'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}.items():assert row['summary'][k]==v
 if label=='original':cls,method=selected.split('/')[1:]
 else:cls,method='OriginalFocusPositiveTests','testActualTypingAndButtonBeforeOriginalAppCase'
 assert re.search(r"Test Case '-\[[^\]\n]*\."+cls+' '+method+r"\]' passed",(a/(label+'.log')).read_text())
assert json.loads((root/'6139-original-xcresult-summary.json').read_text())==d['results']['original']['summary']
build=d['actual_build_configuration']
assert build['CONFIGURATION']=='Debug' and build['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=='DEBUG' and build['FULL_PRODUCT_NAME']=='MacDown2.app' and build['PRODUCT_BUNDLE_IDENTIFIER']=='app.mostlytext.MostlyText'
assert d['built_before']['path']==d['built_after']['path']==build['TARGET_BUILD_DIR']+'/MacDown2.app'
for stage in ['built_before','built_after']:assert d[stage]['info']['CFBundleIdentifier']=='app.mostlytext.MostlyText'
target=d['actual_original_target'];assert target=={'TestHostPath':'__TESTROOT__/Debug/MacDown2UITests-Runner.app','TestBundlePath':'__TESTHOST__/Contents/PlugIns/MacDown2UITests.xctest','UITargetAppPath':'__TESTROOT__/Debug/MacDown2.app','IsUITestBundle':True}
for p,h in d['actual_xctestruns'].items():assert sha((a/p).read_bytes())==h
assert sha((a/'test-inputs/MacDown2UITests').read_bytes())==d['test_executable_sha256']
facts=d['actual_gui'];assert facts['uid']==501 and facts['on_console'] and facts['login_done'] and facts['screen_lock_field'] is not True and facts['keyboard_input_source']=='com.apple.keylayout.US' and facts['screens']
commands=d['commands'];original=next(c for c in commands if c['label']=='original');assert '-only-testing:'+selected in original['arguments'] and original['returncode']==0
assert d['built_before']['executable_sha256']==json.loads((a/'original-owned/identity.json').read_text())['app_sha256']
assert all(c['returncode']==0 for c in commands)
proof={'actual_tested_tree':git('rev-parse','2c89329b065466b160faf68a7fa96148df7ad829^{tree}').decode().strip(),'all_bound_source_inputs_equal_across_documentation_base':True,'head':head,'checkout':d['checkout'],'tree':tree,'all_source_inputs_verified':len(expected),'all_pins_verified':24,'all_generated_control_inputs_verified':len(d['generated_sha256']),'actual_selected_original':selected,'original_case_and_private_positive_actual_passes':2,'failures_skips_expected_failures':0,'positive_owned':d['results']['positive']['owned'],'original_owned':d['results']['original']['owned'],'actual_gui':facts,'actual_intentional_configuration':build,'actual_xctestrun_targets_verified':target,'downloaded_compiled_test_input_sha256_verified':d['test_executable_sha256'],'recorded_app_before_sha256':d['built_before']['executable_sha256'],'recorded_app_after_sha256':d['built_after']['executable_sha256'],'original_named_focus_source_byte_identical_main':True,'scope':'Genuine original named Debug engineering focus case after real private typing/counter0-to1 control. Runtime actual counts/log identity and configured target verified. Test input binary downloaded; app binary hashes/signatures are hosted before/after records, not independently downloaded app or normal Release/exact-artifact/protected owner/full critical acceptance. No post-close fixture-byte fidelity inferred.'}
(root/'6139-original-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n')
print({k:v for k,v in proof.items() if not isinstance(v,dict)})
