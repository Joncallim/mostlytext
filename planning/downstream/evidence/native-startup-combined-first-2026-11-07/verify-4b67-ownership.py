import hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent;a=root/'4b67-startup-artifact/placeholder-window-classifier';repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='4b6717905aaabb4053f20589ec323905d86dcef6';base='ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9';git=lambda *args:subprocess.check_output(['git',*args],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest();r=json.loads((a/'receipt.json').read_text());checkout=r['checkout']
assert git('show','-s','--format=%P',checkout).decode().split()==[base,head]
assert git('merge-tree','--write-tree',base,head).decode().strip()==git('rev-parse',checkout+'^{tree}').decode().strip()
paths=git('ls-tree','-r','--name-only',checkout,'--','MacDown2','.github/placeholder-window-probe','.github/scripts/run-placeholder-window-probe.py','.github/scripts/prepare-hosted-public-focus.py','.github/scripts/test-hosted-focus-guard.py','.github/scripts/run-owned-app-tests.py','.github/scripts/test-run-owned-app-tests.py','.github/workflows/placeholder-window-probe.yml').decode().splitlines()
assert set(paths)==set(r['canonical_source_sha256'])
requests=[checkout+':'+p for p in paths];stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for req in requests:
 hdr=stream.readline().split();assert hdr[1]==b'blob';raw=stream.read(int(hdr[2]));assert stream.read(1)==b'\n';p=req.split(':',1)[1];assert sha(raw)==r['canonical_source_sha256'][p],p;blobs[p]=raw
assert r['executed_source_sha256']==r['canonical_source_sha256']
c=r['controlled_test_input'];assert c['canonical_addition'] is False
assert (a/'executed-PlaceholderOwnershipProbeTests.swift').read_bytes()==blobs[c['executed']]==blobs[c['source']]==git('show','1382581d585c1dd0a6c6fde0435d011ddb5f5f13:.github/placeholder-window-probe/PlaceholderOwnershipProbeTests.swift')
assert c['sha256']==sha(blobs[c['executed']])
assert r['pins']==json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins'] and len(r['pins'])==24
for p,h in r['xctestrun_sha256'].items():assert sha((a/p).read_bytes())==h
summary=json.loads((root/'4b67-ownership-actual-summary.json').read_text());assert summary==r['actual_summary']
expected={'totalTestCount':4,'passedTests':4,'failedTests':0,'skippedTests':0,'expectedFailures':0}
for k,v in expected.items():assert type(summary[k]) is int and summary[k]==v
assert summary['testFailures']==[] and summary['result']=='Passed'
owned=json.loads((a/'probe-owned/status.json').read_text());assert owned==r['owned'] and r['command_returncode']==owned['returncode']==0 and owned['timed_out'] is False and owned['cancelled'] is False and owned['app_cleanup_requested']==[] and 0<owned['elapsed_seconds']<600
assert r['mode']=='verify-fix' and r['source_verified_after'] is True and r['controlled_outcome_verified'] is True
log=(a/'probe.log').read_text()
for name in ['unmarkedWindowsAreNotStartupPlaceholders','theFirstRunWelcomeWindowIsNotAPlaceholder','anExplicitlyMarkedStartupWindowIsAPlaceholder','attachingTheStartupMarkerMarksItsOwnWindow']:
 assert re.search(r'Test '+name+r'\(\) passed',log),name
assert '** TEST BUILD SUCCEEDED **' in (a/'build.log').read_text()
proof={'head':head,'checkout':checkout,'tree':git('rev-parse',head+'^{tree}').decode().strip(),'all_canonical_and_executed_inputs_verified':len(paths),'pins_verified':24,'canonical_regression_byte_identical_to_genuine_before_failure':True,'no_additional_derived_test_source':True,'actual_xcresult_summary_independently_read':True,'actual_counts':expected,'actual_owned':owned,'all_four_actual_case_identities_verified':True,'hosted_executable_sha256_recorded_not_downloaded':r['built']['executable_sha256'],'full_logs_sha256':sha((root/'4b67-startup-full-logs.zip').read_bytes()),'scope':'Actual scoped four-case component pass after genuine before-fix failure. Not complete CI, public normal UI, protected owner, full critical matrix, Preview repair, or signed-artifact acceptance.'}
(root/'4b67-ownership-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps(proof,indent=2))
