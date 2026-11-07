import hashlib,io,json,pathlib,subprocess
root=pathlib.Path(__file__).parent;p=root/'43e1-cli-artifact/normal-release-public-cli';r=json.loads((p/'native-cli-proof/receipt.json').read_text());repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';head='43e1b04c7e141a7b007dd48e9d26f011ebe3a121'
def git(*args):return subprocess.check_output(['git',*args],cwd=repo,text=True).strip()
assert git('show','-s','--format=%P',r['source_head']).split() == ['ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9', head]
assert git('merge-tree','--write-tree','ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9',head).splitlines()[0] == git('rev-parse',r['source_head']+'^{tree}')
paths=['MacDown2','.github/scripts/native-cli-app-host.swift','.github/scripts/run-native-cli-probe.py','.github/workflows/native-cli-probe.yml','.github/scripts/run-owned-app-tests.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/native_cli_endpoint_probe.py','.github/scripts/test-native-cli-endpoint-probe.py'];expected=set(git('ls-tree','-r','--name-only',head,'--',*paths).splitlines());assert expected==set(r['source_sha256'])
requests=[head+':'+n for n in sorted(expected)];stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()));blobs={}
for key in requests:
 hdr=stream.readline().split();assert hdr[1]==b'blob';raw=stream.read(int(hdr[2]));assert stream.read(1)==b'\n';name=key.split(':',1)[1];assert hashlib.sha256(raw).hexdigest()==r['source_sha256'][name],name;blobs[name]=raw
assert json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins']==r['pins']
identity=json.loads((p/'native-cli-owned/identity.json').read_text());status=json.loads((p/'native-cli-owned/status.json').read_text());assert identity['checkout']==r['source_head'] and identity['app_sha256']==r['app_sha256'];assert status['returncode']==0 and not status['timed_out'] and not status['cancelled']
rows=r['commands'];by_label={x['label']:x for x in rows}
expected_criteria={'fresh_warm_file':True,'configured_warm_file':True,'missing_file_rejected':True,'wait_completed_after_normal_quit':True,'configured_stdin_acknowledged':True,'invalid_utf8_rejected':True}
assert r['criteria']==expected_criteria and r['passed'] and not r['errors'] and not r.get('observation_errors')
for label,code in [('fresh-warm-file',0),('configured-warm-file',0),('missing-file',4),('wait-completes-after-normal-app-termination',0),('configured-implicit-stdin',0),('invalid-utf8-stdin',3)]:assert by_label[label]['returncode']==code,label
assert all(not x.get('timed_out') for x in rows) and r['first_run_endpoint_observed']
apps=r['applications'];launches=[x for x in apps if x['operation']=='launch'];assert len(launches)==3
for label in ['fresh-before-file','fresh-after-file']:
 windows=json.loads((p/'native-cli-proof'/(label+'-windows.json')).read_text());assert windows['pid']==launches[0]['pid'] and windows['window_metadata_available']
 assert any(x.get('name')=='Welcome to MostlyText' and x.get('kCGWindowIsOnscreen') for x in windows['windows'])
 row=by_label[label+'-first-run-key'];assert row['returncode']==1 and 'does not exist' in row['stderr']
assert len(r['welcome_observations'])==2 and all(not x['first_run_acknowledged'] and x['pid']==launches[0]['pid'] for x in r['welcome_observations'])
for index,launch in enumerate(launches):
 operation='cleanup' if index==2 else 'terminate'
 action=next(x for x in rows if x['label']=='app-'+operation and x['command'][-2]==str(launch['pid']))
 assert float(action['command'][-1])==launch['birth'] and action['returncode']==0
 if index<2:
  ending=next(x for x in apps if x['pid']==launch['pid'] and x['operation']==operation)
  assert ending['terminated'] and ending['executable']==launch['executable']
 else:
  ending=next(x for x in apps if x['operation']=='cleanup')
  assert ending['terminated'] and ending['pid'] in [-1,launch['pid']] and ending['executable']==launch['executable'], 'Verify the actual post-force state without inferring prior exit timing or normal Quit'
q=p/'native-cli-proof';source=next(q.glob('space *.md'));assert source.read_bytes()==b'# Native CLI fixture\r\n\r\nUntouched source.\r\n' and hashlib.sha256(source.read_bytes()).hexdigest()==r['source_file_sha256']
stdin=(q/'stdin-source.md').read_bytes();assert hashlib.sha256(stdin).hexdigest()==r['stdin_sha256']
controls=r['endpoint_probe_controls'];assert controls['passed'] and controls['tests']==6 and not controls['failures'] and not controls['errors']
assert controls['module_sha256']==r['source_sha256']['.github/scripts/native_cli_endpoint_probe.py'] and controls['script_sha256']==r['source_sha256']['.github/scripts/test-native-cli-endpoint-probe.py']
control_bytes=(p/'native-cli-endpoint-controls.json').read_bytes();assert hashlib.sha256(control_bytes).hexdigest()==r['endpoint_probe_controls_sha256'] and json.loads(control_bytes)==controls
assert len(r['endpoint_readiness'])==3
for launch,observation in zip(launches,r['endpoint_readiness']):
 assert observation['pid']==launch['pid'] and observation['ready'] and observation['application_frames_sent']==0
 attempts=observation['attempts'];assert attempts[-1]['ready'] and attempts[-1]['peer_pid']==launch['pid'] and attempts[-1]['peer_uid']==501 and attempts[-1]['mode']=='0o600'
 assert 0<attempts[-1]['elapsed_seconds']<10 and all(not x['ready'] for x in attempts[:-1])
record={'head' :head,'checkout':r['source_head'],'full_source_hashes_verified':len(r['source_sha256']),'pins_verified':len(r['pins']),'owned_status':status,'criteria':r['criteria'],'fresh_welcome_and_acknowledgement_raw_observations_verified':True,'strict_actual_identity_arguments_and_normal_first_two_quits_verified':True,'app_sha256':r['app_sha256'],'helper_sha256':r['helper_sha256'],'post_force_cleanup_returned_pid':ending['pid'],'live_matching_actual_peers_verified':3,'hosted_kernel_controls_verified':6,'scope':'All six actual CLI comparisons pass, fresh Welcome/key preserved, both normal Quits verified. Transport-only readiness opens prior connections; not cold/first-client/installed/owner/signed acceptance or saved stdin fidelity.'}
(root/'43e1-cli-first-outcome-independently-verified.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
