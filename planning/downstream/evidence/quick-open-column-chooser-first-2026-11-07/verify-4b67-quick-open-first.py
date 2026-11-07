import hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='4b6717905aaabb4053f20589ec323905d86dcef6';base='ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9';checkout='b61451098b8b5c068e13b20853e55414cee9a036';git=lambda *args:subprocess.check_output(['git',*args],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest()
paths=['MacDown2','.github/hosted-original-focus','.github/hosted-public-focus','.github/scripts/prepare-hosted-public-focus.py','.github/scripts/run-hosted-original-focus.py','.github/scripts/run-owned-app-tests.py','.github/scripts/test-hosted-focus-guard.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/check-native-ui-required-cases.py','.github/scripts/test-native-ui-required-cases.py','planning/downstream/native-ui-required-cases.json','.github/workflows/hosted-original-focus.yml','.github/scripts/run-hosted-critical-journey.py','.github/scripts/test-hosted-critical-journey.py','.github/workflows/hosted-critical-journeys.yml']
expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines());requests=[head+':'+p for p in sorted(expected)];stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for req in requests:
 hdr=stream.readline().split();assert hdr[1]==b'blob';raw=stream.read(int(hdr[2]));assert stream.read(1)==b'\n';blobs[req.split(':',1)[1]]=raw
assert git('show','-s','--format=%P',checkout).decode().split()==[base,head]
tree=git('rev-parse',head+'^{tree}').decode().strip();assert git('rev-parse',checkout+'^{tree}').decode().strip()==git('merge-tree','--write-tree',base,head).decode().strip();assert set(git('diff','--name-only',base,head,'--','MacDown2').decode().splitlines())=={'MacDown2/MacDown2/AppDelegate.swift','MacDown2/MacDown2/MacDown2App.swift','MacDown2/MacDown2UITests/TabLifecycleUITests.swift'}
assert set(git('ls-tree','-r','--name-only',checkout,'--',*paths).decode().splitlines())==expected
requests2=[checkout+':'+p for p in sorted(expected)];actual_stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests2)+'\n').encode()))
for request in requests2:
 header=actual_stream.readline().split();assert header[1]==b'blob';raw=actual_stream.read(int(header[2]));assert actual_stream.read(1)==b'\n';assert raw==blobs[request.split(':',1)[1]]
selected={'native-tabs-quick-open':('TabLifecycleUITests','testQuickOpenReactivatesAnAlreadyOpenBackgroundTab')};records=[]
for journey,(cls,method) in selected.items():
 a=root/'4b67-quick-open-first-artifact';d=json.loads((a/'receipt.json').read_text());case='MacDown2UITests/'+cls+'/'+method
 assert d['checkout']==checkout and set(d['source_sha256'])==expected
 for p,h in d['source_sha256'].items():assert sha(blobs[p])==h,p
 assert d['pins']==json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins'] and len(d['pins'])==24
 assert d['critical_journey_binding']=={'journey':journey,'qualified_main':'6b49777d0f36c3d7a23cd0089e0823da1986660a','selected_original':case} and d['selected_original']==case
 for p,h in d['generated_sha256'].items():assert sha((a/'fixture'/p).read_bytes())==h,p
 for source,target in d['fixture_mapping'].items():assert sha(blobs[source])==d['generated_sha256'][target],source
 for p,h in d['actual_xctestruns'].items():assert sha((a/p).read_bytes())==h
 assert sha((a/'test-inputs/MacDown2UITests').read_bytes())==d['test_executable_sha256']
 code=d['results']['original']['owned']['returncode'];assert type(code) is int and code in [0,65]
 for label,expected_code in [('positive',0),('original',code)]:
  row=d['results'][label];actual=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/(label+'.xcresult'))]));(root/('4b67-'+journey+'-'+label+'-actual-summary.json')).write_text(json.dumps(actual,indent=2)+'\n');assert actual==row['summary']
  status=json.loads((a/(label+'-owned/status.json')).read_text());assert row['owned']==status and status['returncode']==expected_code and status['timed_out'] is False and status['cancelled'] is False and status['app_cleanup_requested']==[]
  counts={'totalTestCount':1,'passedTests':int(expected_code==0),'failedTests':int(expected_code!=0),'skippedTests':0,'expectedFailures':0}
  for k,v in counts.items():assert type(actual[k]) is int and actual[k]==v
  if label=='positive':c,m='OriginalFocusPositiveTests','testActualTypingAndButtonBeforeOriginalAppCase'
  else:c,m=cls,method
  pattern=r"Test Case '-\[[^\]\n]*\."+re.escape(c)+' '+re.escape(m)+r"\]' "+('passed' if expected_code==0 else 'failed');assert re.search(pattern,(a/(label+'.log')).read_text()),journey
  if expected_code:assert len(actual['testFailures'])==1 and actual['testFailures'][0]['testIdentifierString']==cls+'/'+method+'()'
 build=d['actual_build_configuration'];assert build['CONFIGURATION']=='Debug' and build['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=='DEBUG' and build['PRODUCT_BUNDLE_IDENTIFIER']=='app.mostlytext.MostlyText'
 target=d['actual_original_target'];assert target=={'TestHostPath':'__TESTROOT__/Debug/MacDown2UITests-Runner.app','TestBundlePath':'__TESTHOST__/Contents/PlugIns/MacDown2UITests.xctest','UITargetAppPath':'__TESTROOT__/Debug/MacDown2.app','IsUITestBundle':True}
 facts=d['actual_gui'];assert facts['uid']==501 and facts['on_console'] and facts['login_done'] and facts['keyboard_input_source']=='com.apple.keylayout.US' and facts['screens']
 original=next(c for c in d['commands'] if c['label']=='original');assert original['returncode']==code and '-only-testing:'+case in original['arguments']
 assert d['built_before']['executable_sha256']==json.loads((a/'original-owned/identity.json').read_text())['app_sha256']
 if code==0:assert d['passed'] is True and d['source_unchanged_after'] is True and not d['errors']
 else:assert d['passed'] is False and d['errors']==[{'type':'RuntimeError','message':'original has a genuine failed owned outcome'}]
 records.append({'journey':journey,'selected':case,'source_inputs_verified':len(expected),'pins_verified':24,'generated_inputs_verified':len(d['generated_sha256']),'actual_private_positive_pass':True,'actual_original_summary':d['results']['original']['summary'],'actual_original_owned':d['results']['original']['owned'],'actual_case_identity_verified':True,'test_binary_downloaded_sha256':d['test_executable_sha256'],'source_verified_after_field':d.get('source_unchanged_after'),'app_before_sha256':d['built_before']['executable_sha256'],'app_after_sha256':d['built_after']['executable_sha256'],'framework_runner_restart_after_failure':'Restarting after unexpected' in (a/'original.log').read_text()})
proof={'actual_tested_tree':git('rev-parse','b61451098b8b5c068e13b20853e55414cee9a036^{tree}').decode().strip(),'all_bound_source_inputs_equal_across_documentation_base':True,'head':head,'checkout':checkout,'tree':tree,'exact_three_reviewed_canonical_file_changes':True,'genuine_original_passes':sum(x['actual_original_summary']['passedTests'] for x in records),'genuine_original_failures':sum(x['actual_original_summary']['failedTests'] for x in records),'single_selected_private_positive_pass':True,'rows':records,'scope':'First failed Quick Open precondition and its genuine positive only; not the other two critical journeys. Exact source/pin/generated/testbinary/xctestrun/GUI/owned/actual summary/log bindings verified; real statuses preserved. Failed or framework-restarted cases remain failed/uncertain. No sole historical cause, unchanged retry, post-teardown fixture-byte fidelity, protected owner/full38/sixextra/repeated/final signed acceptance inferred.'}
(root/'4b67-quick-open-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print({k:v for k,v in proof.items() if k!='rows'})
