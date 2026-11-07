import ast,collections,hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent
repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext'
head='4b6717905aaabb4053f20589ec323905d86dcef6'
checkout='b61451098b8b5c068e13b20853e55414cee9a036'
base='ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9'
git=lambda *a:subprocess.check_output(['git',*a],cwd=repo)
sha=lambda b:hashlib.sha256(b).hexdigest()
source=ast.parse(git('show',head+':.github/scripts/run-hosted-ui-batch.py').decode())
corpus=next(ast.literal_eval(n.value) for n in source.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='GUARD_CORPUS' for t in n.targets))
calls=[n for n in ast.walk(source) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='output' and n.args and isinstance(n.args[0],ast.List)]
ls=next(n.args[0] for n in calls if len(n.args[0].elts)>1 and isinstance(n.args[0].elts[1],ast.Constant) and n.args[0].elts[1].value=='ls-files')
constants=[x.value for x in ls.elts if isinstance(x,ast.Constant)]
paths=constants[constants.index('--')+1:]+[p for pair in corpus.values() for p in pair]
expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines())
assert {p for pair in corpus.values() for p in pair} <= expected
requests=[head+':'+p for p in sorted(expected)]
stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for req in requests:
 hdr=stream.readline().split();assert hdr[1]==b'blob';data=stream.read(int(hdr[2]));assert stream.read(1)==b'\n';blobs[req.split(':',1)[1]]=data
assert git('show','-s','--format=%P',checkout).decode().split()==[base,head]
assert git('rev-parse',checkout+'^{tree}').decode().strip()==git('merge-tree','--write-tree',base,head).decode().strip()
assert git('diff','--name-only',head,checkout,'--',*paths).decode().strip()==''
plan=json.loads(blobs['planning/downstream/native-ui-hosted-batches.json']);ids=[c for group in plan['batches'] for c in group['cases']]
manifest=json.loads(blobs['planning/downstream/native-ui-required-cases.json']);assert len(ids)==len(set(ids))==38 and ids==sorted(x['id'] for x in manifest['cases'])
raw=blobs[plan['actualDiscoveryPath']];assert sha(raw)==plan['actualDiscoverySHA256'];actual=json.loads(raw);assert actual['errors']==[]
assert sorted(x['identifier'][:-2] for v in actual['values'] for x in v['enabledTests'] if x['identifier'].startswith('MacDown2UITests/'))==ids
records=[];batches=[];pending=[]
for group in plan['batches']:
 label=group['id'];a=root/('4b67-'+label+'-artifact')
 if not (a/'receipt.json').exists():pending.append(label);continue
 d=json.loads((a/'receipt.json').read_text())
 assert d['checkout']==checkout and set(d['source_sha256'])==expected
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
 for key,result in d['results'].items():
  summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/(key+'.xcresult'))]))
  assert summary==result['summary']
  owned=json.loads((a/(key+'-owned/status.json')).read_text());assert owned==result['owned'] and not owned['timed_out'] and not owned['cancelled'] and owned['app_cleanup_requested']==[]
  for k,v in {'totalTestCount':1,'skippedTests':0,'expectedFailures':0}.items():assert type(summary[k]) is int and summary[k]==v
  selected=result['selected'];target,cls,method=selected.split('/');log=(a/(key+'.log')).read_text()
  pattern=r"Test Case '-\["+re.escape(target)+r'\.'+re.escape(cls)+' '+re.escape(method)+r"\]' "
  assert len(re.findall(pattern+'started',log))==1
  if summary['passedTests']==1:
   assert summary['failedTests']==0 and owned['returncode']==0 and result['passed'] is True and len(re.findall(pattern+'passed',log))==1 and not re.search(pattern+'failed',log) and 'Restarting after unexpected' not in log
  else:
   assert summary['passedTests']==0 and summary['failedTests']==1 and owned['returncode']==65 and len(re.findall(pattern+'failed',log))==1 and not re.search(pattern+'passed',log)
  identity=json.loads((a/(key+'-owned/identity.json')).read_text());assert identity['checkout']==checkout
  if key!='positive':assert identity['app_sha256']==d['built_before']['executable_sha256']
 assert d['results']['positive']['passed'] is True
 for row in d['batch_cases']:
  state=row['status'];entry={'batch':label,'selected':row['selected'],'controller_status':state,'source_after_verified':row.get('source_and_products_verified_after',False)}
  if state=='PASSED':
   result=d['results'][row['result_label']];assert row['source_and_products_verified_after'] is True and row['app_after']==d['built_before'] and result['passed'] is True;entry.update(actual_passed=1,actual_failed=0,owned=result['owned'])
  elif state in ['FAILED','INCOMPLETE']:
   result=d['results'][row['result_label']];assert result['summary']['failedTests']==1;entry.update(actual_passed=0,actual_failed=1,framework_restarted='Restarting after unexpected' in (a/(row['result_label']+'.log')).read_text(),owned=result['owned'])
  else:
   assert state=='NOT_RUN' and row['reason'];entry.update(actual_passed=0,actual_failed=0,not_run=True)
  records.append(entry)
 if d['passed']:assert d['errors']==[] and d['source_unchanged_after'] is True and all(r['status']=='PASSED' for r in d['batch_cases'])
 else:assert d['errors']
 batches.append({'batch':label,'canonical_inputs_verified':len(expected),'all_four_guard_corpus_hashes_included':True,'pins':24,'generated_inputs_verified':len(d['generated_sha256']),'actual_positive_passed':True,'downloaded_compiled_test_sha256':d['test_executable_sha256'],'all_original_rows_passed':d['passed']})
assert len({r['selected'] for r in records})==len(records)
if not pending:assert len(records)==38 and {r['selected'] for r in records}==set(ids)
counts=dict(collections.Counter(r['controller_status'] for r in records))
proof={'head':head,'actual_checkout':checkout,'actual_tree':git('rev-parse',checkout+'^{tree}').decode().strip(),'source_tree':git('rev-parse',head+'^{tree}').decode().strip(),'actual_completed_batches_independently_reviewed':len(batches),'pending_batches':pending,'rows_reviewed':len(records),'counts':counts,'all38_originals_pass':not pending and counts=={'PASSED':38},'batch_proofs':batches,'original_rows':records,'scope':'Actual first outcomes only at frozen changed source. Complete canonical/corpus/generated/pin/compiled-test/xctestrun/GUI/owned/actual summary/log bindings independently verified for downloaded batches. Pending, failed or uncertain rows are not passes. No repeated/final/protected/signed/six additional acceptance inferred.'}
(root/'4b67-matrix-first-outcomes-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n')
print({k:v for k,v in proof.items() if k not in ['batch_proofs','original_rows']})
