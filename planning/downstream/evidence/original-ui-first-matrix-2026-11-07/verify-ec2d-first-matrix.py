import ast,collections,hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='ec2ddcb72e65b88dc71f1267b1b4d0b4a47f68c3';checkout='53247e6b2f3bbe4b2d91f458df02638c954f0230';base='210f46b7f94fdbbf0e8dcc14f2a3cd6c1b306ab3'
git=lambda *a:subprocess.check_output(['git',*a],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest()
source=git('show',head+':.github/scripts/run-hosted-ui-batch.py').decode();tree=ast.parse(source)
calls=[n for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='output' and n.args and isinstance(n.args[0],ast.List)]
ls=next([x.value for x in n.args[0].elts] for n in calls if len(n.args[0].elts)>1 and isinstance(n.args[0].elts[1],ast.Constant) and n.args[0].elts[1].value=='ls-files');paths=ls[ls.index('--')+1:]
expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines());requests=[head+':'+p for p in sorted(expected)];stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for req in requests:
 hdr=stream.readline().split();assert hdr[1]==b'blob';data=stream.read(int(hdr[2]));assert stream.read(1)==b'\n';blobs[req.split(':',1)[1]]=data
assert git('show','-s','--format=%P',checkout).decode().split()==[base,head]
assert git('rev-parse',checkout+'^{tree}')==git('rev-parse',head+'^{tree}')
plan=json.loads(blobs['planning/downstream/native-ui-hosted-batches.json']);ids=[c for group in plan['batches'] for c in group['cases']];manifest=json.loads(blobs['planning/downstream/native-ui-required-cases.json']);assert len(ids)==len(set(ids))==38 and ids==sorted(x['id'] for x in manifest['cases'])
raw=blobs[plan['actualDiscoveryPath']];assert sha(raw)==plan['actualDiscoverySHA256'];actual_discovery=json.loads(raw);assert actual_discovery['errors']==[];actualui=sorted(x['identifier'][:-2] for v in actual_discovery['values'] for x in v['enabledTests'] if x['identifier'].startswith('MacDown2UITests/'));assert actualui==ids
records=[];batch_proofs=[]
for group in plan['batches']:
 label=group['id'];a=root/('ec2d-'+label+'-artifact');d=json.loads((a/'receipt.json').read_text());assert d['checkout']==checkout and set(d['source_sha256'])==expected
 for p,h in d['source_sha256'].items():assert sha(blobs[p])==h,(label,p)
 assert d['pins']==json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins'] and len(d['pins'])==24
 assert d['batch_contract']['batch']==label and d['batch_contract']['cases']==group['cases'] and d['batch_contract']['all_discovered_ui_ids']==ids
 assert d['execution_started'] is True
 for p,h in d['generated_sha256'].items():assert sha((a/'fixture'/p).read_bytes())==h,(label,p)
 for p,mapped in d['fixture_mapping'].items():assert sha(blobs[p])==d['generated_sha256'][mapped]
 for p,h in d['actual_xctestruns'].items():assert sha((a/p).read_bytes())==h
 assert sha((a/'test-inputs/MacDown2UITests').read_bytes())==d['test_executable_sha256']
 build=d['actual_build_configuration'];assert build['CONFIGURATION']=='Debug' and build['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=='DEBUG' and build['PRODUCT_BUNDLE_IDENTIFIER']=='app.mostlytext.MostlyText'
 facts=d['actual_gui'];assert facts['uid']==501 and facts['on_console'] and facts['login_done'] and facts['screen_lock_field'] is not True and facts['keyboard_input_source']=='com.apple.keylayout.US' and facts['screens']
 assert d['built_before']==d['built_after']
 assert [x['selected'] for x in d['batch_cases']]==group['cases']
 for result_label,result in d['results'].items():
  summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/(result_label+'.xcresult'))]));assert summary==result['summary'];owned=json.loads((a/(result_label+'-owned/status.json')).read_text());assert owned==result['owned'] and not owned['timed_out'] and not owned['cancelled'] and owned['app_cleanup_requested']==[]
  for k,v in {'totalTestCount':1,'skippedTests':0,'expectedFailures':0}.items():assert type(summary[k]) is int and summary[k]==v
  selected=result['selected'];target,cls,method=selected.split('/');log=(a/(result_label+'.log')).read_text();pattern=r"Test Case '-\["+re.escape(target)+r'\.'+re.escape(cls)+' '+re.escape(method)+r"\]' "
  assert len(re.findall(pattern+'started',log))==1
  if summary['passedTests']==1:
   assert summary['failedTests']==0 and owned['returncode']==0 and result['passed'] is True and len(re.findall(pattern+'passed',log))==1 and not re.search(pattern+'failed',log)
  else:
   assert summary['passedTests']==0 and summary['failedTests']==1 and owned['returncode']==65 and len(re.findall(pattern+'failed',log))==1 and not re.search(pattern+'passed',log)
   assert label=='B06' and result_label=='case-02' and 'FirstRunUITests.swift:61: error:' in log and 'Restarting after unexpected' in log
  identity=json.loads((a/(result_label+'-owned/identity.json')).read_text());assert identity['checkout']==checkout
  if result_label!='positive':assert identity['app_sha256']==d['built_before']['executable_sha256']
 for row in d['batch_cases']:
  state=row['status'];entry={'batch':label,'selected':row['selected'],'controller_status':state,'source_after_verified':row.get('source_and_products_verified_after',False)}
  if state=='PASSED':
   result=d['results'][row['result_label']];assert row['source_and_products_verified_after'] is True and row['app_after']==d['built_before'] and result['passed'] is True;entry.update(actual_passed=1,actual_failed=0,owned=result['owned'])
  elif state=='INCOMPLETE':
   assert label=='B06' and row['result_label']=='case-02';result=d['results'][row['result_label']];assert result['summary']['failedTests']==1;entry.update(actual_passed=0,actual_failed=1,framework_restarted=True,owned=result['owned'])
  else:
   assert label=='B06' and state=='NOT_RUN' and 'Stopped after RuntimeError' in row['reason'];entry.update(actual_passed=0,actual_failed=0,not_run=True)
  records.append(entry)
 if label=='B06':assert d['passed'] is False and len(d['errors'])==1 and d.get('source_unchanged_after') is not True
 else:assert d['passed'] is True and d['errors']==[] and d['source_unchanged_after'] is True
 batch_proofs.append({'batch':label,'canonical_inputs_verified':len(expected),'pins':24,'generated_control_inputs':len(d['generated_sha256']),'actual_private_positive_passed':True,'test_binary_downloaded_sha256':d['test_executable_sha256'],'all_rows_passed':d['passed']})
assert len(records)==38 and len({x['selected'] for x in records})==38
counts=collections.Counter(x['controller_status'] for x in records);assert counts=={'PASSED':35,'INCOMPLETE':1,'NOT_RUN':2},counts
omitted_gate_corpus=['planning/downstream/evidence/qualified-startup-status-2026-11-07/ed96-status-layout--hosted-normal-status-layout--receipt.json.gz','planning/downstream/evidence/qualified-startup-status-2026-11-07/ed96-status-layout--hosted-normal-status-layout--focus.log.gz','planning/downstream/evidence/status-bar-layout-2026-11-07/8e2c-status-receipt.json.gz','planning/downstream/evidence/status-bar-layout-2026-11-07/8e2c-status-focus.log.gz'];assert not(set(omitted_gate_corpus)&expected)
proof={'head':head,'actual_checkout':checkout,'tree':git('rev-parse',head+'^{tree}').decode().strip(),'exact_original_ids':38,'actual_original_passed':35,'actual_original_failed_with_framework_restart':1,'not_run_after_uncertainty':2,'actual_positive_passes':10,'all_source_app_control_scripts_plan_pins_and_compiled_test_bindings_verified':True,'gate_test_corpus_paths_missing_from_producer_source_hash_set':omitted_gate_corpus,'batch_proofs':batch_proofs,'original_rows':records,'scope':'First actual matrix is35passed/1genuine assertion failure with later framework restart/2notrun, never38pass. All actual xcresult summaries/log identities/source/pins/generated/test binaries/owned outcomes reviewed. Four guard-test proof-data files were not included in producer hash map; immutable commit binds repository versions but no after-run bytes were captured for those assets. Correct this binding gap before next candidate. Historical firstRun callback queue unknown; original failure/uncertainty remains. Not sixextra/repeated/final/protected/signed acceptance.'}
(root/'ec2d-first-matrix-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print({k:v for k,v in proof.items() if k not in ['original_rows','batch_proofs']})
