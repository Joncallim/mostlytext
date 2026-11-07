import hashlib,io,json,pathlib,plistlib,re,subprocess
r=pathlib.Path(__file__).parent;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='cdee3db55b05cfde0dbebcd7adf8f65ae617a7e6';checkout='1843c068117ca30ffa6175a7e09f0f50c6d11d77';base='ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9'
a=r/'cdee-migration-artifact/hosted-normal-migration';d=json.loads((a/'receipt.json').read_text());git=lambda *args:subprocess.check_output(['git',*args],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest()
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
assert set(d['ui_results'])=={'positive','failure-observation'} and d['errors']==[{'type':'RuntimeError','message':'Normal migration app did not expose the actual peer in10s'}]
apps=d['applications'];assert [x['operation'] for x in apps]==['launch','inspect','cleanup'] and apps[0]['pid']==apps[1]['pid'] and apps[0]['birth']==apps[1]['birth'] and apps[2]['terminated'] is True
assert any(x.get('name')=='MostlyText Migration' and x.get('kCGWindowIsOnscreen') for x in apps[1]['windows'])
endpoint=d['live_endpoints']['first'];assert endpoint['application_frames_sent']==0 and len(endpoint['attempts'])>0 and all(x['exists'] is False and x['ready'] is False and x['errno']==2 for x in endpoint['attempts'])
rows=plistlib.loads((a/'migration-domains-seeded.plist').read_bytes());assert [x['present'] for x in rows]==[True,False,False,False,False,False]
assert json.loads(rows[0]['value']['appSettings.editor'])['indentationWidth']==2 and rows[0]['value']['com.joncallim.macdown2.hasCompletedFirstRun'] is True
snapshot=json.loads((a/'profile-seeded.json').read_text());assert snapshot['state']==snapshot['preserved']==snapshot['installation']=={}
for name,row in snapshot['old'].items():
 if row['kind']=='file':assert sha((a/'profile-seeded-old'/name).read_bytes())==row['sha256']
seed=json.loads((a/'migration-seed.json').read_text());assert len(seed['session']['tabs'])==2 and sha((a/'migration-seed.json').read_bytes())==d['migration_seed_sha256']
observation=d['ui_results']['failure-observation'];actual=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/'failure-observation.xcresult')]))
assert actual==observation['summary'] and observation['selected']=='HostedFocusDriverTests/PublicFocusTests/testObserveFailedMigrationStartup'
for k,v in {'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}.items():assert type(actual[k]) is int and actual[k]==v
assert observation['owned']['returncode']==0 and observation['owned']['app_cleanup_requested']==[] and not observation['owned']['timed_out'] and not observation['owned']['cancelled']
assert d['failure_ui_observation_only'] is True and d['migration_failure_after_source_verified'] is True
assert d['migration_failure_original_profile_unchanged'] is True and d['migration_failure_original_domains_unchanged'] is True and d['migration_failure_command_sentinel_exists'] is False
post=json.loads((a/'profile-failure.json').read_text());assert snapshot['old']==post['old']
for kind in ['old','preserved','state','installation']:
 for name,row in post[kind].items():
  if row['kind']=='file':assert sha((a/('profile-failure-'+kind)/name).read_bytes())==row['sha256']
assert set(post['preserved'])==set(snapshot['old'])
for name,row in snapshot['old'].items():
 other=post['preserved'][name]
 assert all(row.get(k)==other.get(k) for k in ['kind','size','sha256']) and other['mode']&0o077==0
failure_domains=plistlib.loads((a/'migration-domains-failure.plist').read_bytes());current=next(x['value'] for x in failure_domains if x['domain']=='app.mostlytext.MostlyText')
for first,last in zip(rows,failure_domains):
 if first['domain']!='app.mostlytext.MostlyText':assert first==last
saved=plistlib.loads((a/'profile-failure-installation/installation-v1/Preferences/current-application.plist').read_bytes());assert saved==current and len(saved)==1
key=next(iter(saved));assert key.startswith('NSWindow Frame SwiftUI.ModifiedContent<MacDown2.StartupPlaceholderView,')
plan=json.loads((a/'profile-failure-installation/installation-plan.json').read_bytes());assert plan['adoptsDevelopment'] is False and plan['beforePreferenceDigests'][0]!='absent' and plan['trees'][2]['entries']==[]
assert set(post['state'])=={'.'} and not d.get('migration_complete') and not d.get('migration_first_ui_passed')
for marker in ['complete','paths','preferences']:
 assert json.loads((a/('profile-failure-installation/installation-'+marker+'.json')).read_bytes())['phase']==marker
ax=(r/'cdee-migration-failure-attachments/6DAADA67-633D-4510-B646-AAE726C6C015.txt').read_text();assert 'value: Your Existing Most...' in ax and 'Continue With Existing Installation' in ax and "identifier: 'app.mostlytext.startup-placeholder'" in ax
proof={'head':head,'actual_checkout':checkout,'actual_tree':git('rev-parse',checkout+'^{tree}').decode().strip(),'canonical_inputs_verified':len(expected),'pins':24,'all_generated_seed_driver_and_four_compiled_downloads_verified':True,'actual_positive_pass':True,'actual_readonly_failure_observation_pass':True,'original_normal_migration_failed_before_adoption_relaunch':True,'complete_source_and_product_verification_after_forced_cleanup':True,'original_profile_inodes_modes_owners_bytes_and_domains_unchanged':True,'preserved_copy_complete_and_private':True,'command_sentinel_absent_after_failure':True,'actual_current_domain_before_launch_absent':True,'only_current_domain_value_in_completed_transaction':current,'actual_plan_adopts_development':False,'actual_current_state_empty':True,'actual_preserved_review_ui_and_completed_paths_preferences_journal_verified':True,'scope':'Concrete first normal startup defect: automatic StartupPlaceholderView saves only a frame preference before migration snapshots current state, so populated=true prevents adoption despite initially absent current domain/state. Journal/current snapshot/UI independently agree. Original6domains/oldprofile preserved; no data loss, successful migration/relaunch, normalQuit or sole broader historical cause inferred. Fix scene lifecycle, not the conservative existing-installation policy.'}
(r/'cdee-migration-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print(proof)
