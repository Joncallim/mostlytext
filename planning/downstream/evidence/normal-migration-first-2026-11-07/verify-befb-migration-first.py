import hashlib,io,json,pathlib,plistlib,re,subprocess
r=pathlib.Path(__file__).parent;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='befb4de00ceef29fdc5a6568e45fcac25133ef5f';checkout='172e8bf93e9f22f163ffbbe805dcc199cd024c54';base='ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9'
a=r/'befb-migration-artifact/hosted-normal-migration';d=json.loads((a/'receipt.json').read_text());git=lambda *args:subprocess.check_output(['git',*args],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest()
assert d['checkout']==checkout and git('show','-s','--format=%P',checkout).decode().split()==[base,head] and git('rev-parse',checkout+'^{tree}')==git('rev-parse',head+'^{tree}')
paths=['MacDown2','.github/hosted-public-focus','.github/scripts/prepare-hosted-public-focus.py','.github/scripts/run-hosted-public-focus.py','.github/scripts/test-hosted-focus-guard.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/native-cli-app-host.swift','.github/scripts/native_cli_endpoint_probe.py','.github/scripts/run-owned-app-tests.py','.github/workflows/hosted-public-focus.yml','.github/workflows/status-bar-layout.yml','.github/workflows/hosted-license-notices.yml','.github/scripts/test-hosted-license-notices.py','LICENSE','compliance/generated/THIRD_PARTY_NOTICES.md','.github/hosted-migration','.github/scripts/prepare-hosted-migration.py','.github/scripts/run-hosted-migration.py','.github/scripts/migration_profile_evidence.py','.github/scripts/test-hosted-migration.py','.github/scripts/test-migration-seed-admission.py','.github/workflows/hosted-migration.yml']
expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).decode().splitlines());assert expected==set(d['source_sha256'])
requests=[head+':'+p for p in sorted(expected)];stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for req in requests:
 h=stream.readline().split();assert h[1]==b'blob';raw=stream.read(int(h[2]));assert stream.read(1)==b'\n';p=req.split(':',1)[1];assert sha(raw)==d['source_sha256'][p],p;blobs[p]=raw
assert len(expected)==1622 and d['pins']==json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins'] and len(d['pins'])==24
for p,h in d['generated_sha256'].items():assert sha((a/'fixture'/p).read_bytes())==h
for p,h in d['seed_generated_sha256'].items():assert sha((a/'seed'/p).read_bytes())==h
assert (a/'seed/Package.resolved').read_bytes()==blobs['MacDown2/Packages/MacDownKit/Package.resolved']
assert sha((a/'seed/.build/release/SeedMigrationProfile').read_bytes())==d['seed_executable_sha256']
assert len(d['migration_compiled_downloads'])==len(d['migration_compiled_sha256'])==4
assert set(d['migration_compiled_downloads'].values())==set(d['migration_compiled_sha256'].values())
for p,h in d['migration_compiled_downloads'].items():assert sha((a/p).read_bytes())==h
assert d['criteria']=={'benign_control':True} and d['migration_execution_started'] is True and not d['passed']
positive=d['ui_results']['positive'];actual=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/'positive.xcresult')]))
assert actual==positive['summary'] and positive['selected']=='HostedFocusDriverTests/PublicFocusTests/testBenignInputControl'
for k,v in {'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}.items():assert type(actual[k]) is int and actual[k]==v
owned=json.loads((a/'positive-owned/status.json').read_text());assert owned==positive['owned'] and owned['returncode']==0 and not owned['timed_out'] and not owned['cancelled'] and owned['app_cleanup_requested']==[]
assert set(d['ui_results'])=={'positive'} and d['errors']==[{'type':'RuntimeError','message':'Normal migration app did not expose the actual peer in10s'}]
apps=d['applications'];assert [x['operation'] for x in apps]==['launch','inspect','cleanup'] and apps[0]['pid']==apps[1]['pid'] and apps[0]['birth']==apps[1]['birth'] and apps[2]['terminated'] is True
assert any(x.get('name')=='MostlyText Migration' and x.get('kCGWindowIsOnscreen') for x in apps[1]['windows'])
endpoint=d['live_endpoints']['first'];assert endpoint['application_frames_sent']==0 and len(endpoint['attempts'])==109 and all(x['exists'] is False and x['ready'] is False and x['errno']==2 for x in endpoint['attempts'])
rows=plistlib.loads((a/'migration-domains-seeded.plist').read_bytes());assert [x['present'] for x in rows]==[True,False,False,False,False,False]
assert json.loads(rows[0]['value']['appSettings.editor'])['indentationWidth']==2 and rows[0]['value']['com.joncallim.macdown2.hasCompletedFirstRun'] is True
snapshot=json.loads((a/'profile-seeded.json').read_text());assert snapshot['state']==snapshot['preserved']==snapshot['installation']=={}
for name,row in snapshot['old'].items():
 if row['kind']=='file':assert sha((a/'profile-seeded-old'/name).read_bytes())==row['sha256']
seed=json.loads((a/'migration-seed.json').read_text());assert len(seed['session']['tabs'])==2 and sha((a/'migration-seed.json').read_bytes())==d['migration_seed_sha256']
proof={'head':head,'actual_checkout':checkout,'actual_tree':git('rev-parse',checkout+'^{tree}').decode().strip(),'complete_canonical_source_inputs_verified':len(expected),'pins_verified':24,'generated_driver_inputs_verified':len(d['generated_sha256']),'generated_seed_inputs_verified':len(d['seed_generated_sha256']),'compiled_seed_sha256':d['seed_executable_sha256'],'four_actual_control_runner_test_binary_xctestrun_downloads_verified':True,'actual_normal_release_app_and_forced_lock_canonical_seed_compilation_succeeded':True,'actual_positive_pass':True,'positive_owned':owned,'normal_app_launched':True,'normal_command_peer_observed':False,'first_and_relaunch_cases':'NOT_RUN','original_profile_generated_and_prelaunch_bytes_identities_domains_verified':True,'post_failure_profile_domains_and_precise_public_failure_state':'NOT_CAPTURED','cleanup':'identity-bound forced cleanup, not normal Quit','scope':'First normal migration rehearsal fails before original first/relaunch UI cases:109 no-peer observations in existing10s and a real migration window remains. No precise blocked-versus-preserved-review state or sole cause captured. Native root-lock/seed/driver compile and actual positive are verified; no migration preservation/adoption/readiness/pass inferred. Preserve first failure before material observability or policy correction.'}
(r/'befb-migration-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print(proof)
