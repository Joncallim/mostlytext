import hashlib,io,json,pathlib,plistlib,re,subprocess
r=pathlib.Path(__file__).parent;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='4b6717905aaabb4053f20589ec323905d86dcef6';checkout='b61451098b8b5c068e13b20853e55414cee9a036';base='ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9'
a=r/'4b67-migration-artifact/hosted-normal-migration';d=json.loads((a/'receipt.json').read_text());git=lambda *args:subprocess.check_output(['git',*args],cwd=repo);sha=lambda b:hashlib.sha256(b).hexdigest()
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
assert set(d['ui_results'])=={'positive','first','failure-observation'}
for label,result in d['ui_results'].items():
 actual=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/(label+'.xcresult'))]))
 assert actual==result['summary']
 wanted={'totalTestCount':1,'passedTests':0 if label=='first' else 1,'failedTests':1 if label=='first' else 0,'skippedTests':0,'expectedFailures':0}
 for k,v in wanted.items():assert type(actual[k]) is int and actual[k]==v
 owned=json.loads((a/(label+'-owned/status.json')).read_text());assert owned==result['owned']
 assert owned['returncode']==(65 if label=='first' else 0) and not owned['timed_out'] and not owned['cancelled'] and owned['app_cleanup_requested']==[]
assert d['errors']==[{'type':'RuntimeError','message':'Uncertain or failed exact migration case: first'}]
failed=d['ui_results']['first']['summary']['testFailures'];assert len(failed)==1 and 'Spaces: 4' in failed[0]['failureText'] and 'Spaces: 2' in failed[0]['failureText']
assert d['ui_results']['first']['selected']=='HostedFocusDriverTests/PublicFocusTests/testNormalDevelopmentProfileAdoption'
apps=d['applications'];assert [x['operation'] for x in apps]==['launch','inspect','cleanup'] and apps[0]['pid']==apps[1]['pid'] and apps[0]['birth']==apps[1]['birth'] and apps[2]['terminated'] is True
assert not d.get('migration_first_ui_passed') and not d.get('migration_first_normal_quit_verified') and not d.get('migration_complete')
assert d['failure_ui_observation_only'] and d['migration_failure_after_source_verified'] and d['migration_failure_original_profile_unchanged'] and d['migration_failure_original_domains_unchanged'] and d['migration_failure_command_sentinel_exists'] is False
before=json.loads((a/'profile-seeded.json').read_text());after=json.loads((a/'profile-failure.json').read_text());assert before['old']==after['old']
for kind in ['old','preserved','state','installation']:
 for name,row in after[kind].items():
  if row['kind']=='file':assert sha((a/('profile-failure-'+kind)/name).read_bytes())==row['sha256']
for name,row in before['old'].items():assert all(row.get(k)==after['preserved'][name].get(k) for k in ['kind','size','sha256'])
rows=plistlib.loads((a/'migration-domains-seeded.plist').read_bytes());post=plistlib.loads((a/'migration-domains-failure.plist').read_bytes());assert [x['present'] for x in rows]==[True,False,False,False,False,False]
for first,last in zip(rows,post):
 if first['domain']!='app.mostlytext.MostlyText':assert first==last
old=rows[0]['value'];current=next(x['value'] for x in post if x['domain']=='app.mostlytext.MostlyText')
assert current['appSettings.editor']==old['appSettings.editor'] and json.loads(current['appSettings.editor'])['indentationWidth']==2
assert current['com.joncallim.macdown2.hasCompletedFirstRun'] is True
plan=json.loads((a/'profile-failure-installation/installation-plan.json').read_bytes());assert plan['adoptsDevelopment'] is True and plan['beforePreferenceDigests']==['absent','absent']
seed=json.loads((a/'migration-seed.json').read_bytes());session=json.loads((a/'profile-failure-state/session.json').read_bytes());assert len(seed['session']['tabs'])==len(session['tabs'])==2 and seed['session']['activeTabID']==session['activeTabID']
for b,c in zip(seed['session']['tabs'],session['tabs']):
 for key in ['id','documentRecoveryEpoch','baseSHA256','encoding']:assert b[key]==c[key]
assert (a/'documents/migration-external.txt').read_bytes().decode()=='Generated external migration document\r\nUnicode: cafe\u0301 \U0001f642\r\n'
ax=(r/'4b67-migration-failure-attachments/43290BC9-3C65-4B6F-9447-7877803A3737.txt').read_text();assert 'Spaces: 4' in ax and 'value: MIGRATION_UNSAVED_...' in ax and 'migration-external.txt' in ax and 'snippets.json' in ax
assert "app.mostlytext.startup-placeholder" not in ax
for phase in ['preferences','paths','complete']:assert json.loads((a/('profile-failure-installation/installation-'+phase+'.json')).read_bytes())['phase']==phase
proof={'head':head,'actual_checkout':checkout,'actual_tree':git('rev-parse',checkout+'^{tree}').decode().strip(),'canonical_inputs_verified':len(expected),'pins':24,'generated_seed_driver_and_four_actual_compiled_downloads_verified':True,'positive_and_readonly_observation_pass':True,'first_adoption_UI_failed':True,'failure':'Actual status Spaces: 4, expected imported2; original two native tabs, active recovery text and absent migration/Welcome surface observed before sole assertion. Root native NSHostingController receives coordinator but no shared appSettings environment; status explicitly falls back to4. Source discrepancy and import publication independently checked; corrected native behavior remains unverified.','current_imported_editor_bytes_equal_original':True,'initial_current_preferences_absent':True,'plan_adopts_development':True,'original_profile_identity_bytes_and_all_other_domains_unchanged':True,'command_sentinel_absent':True,'after_forced_cleanup_full_source_verified':True,'normal_quit_relaunch_and_full_migration_complete':False}
(r/'4b67-migration-first-outcome-independently-verified.json').write_text(json.dumps(proof,indent=2)+'\n');print(proof)
