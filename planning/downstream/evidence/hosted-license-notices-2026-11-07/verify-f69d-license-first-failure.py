import hashlib,io,json,pathlib,re,subprocess
root=pathlib.Path(__file__).parent
a=root/'f69d-license-artifact/hosted-normal-license-notices'
d=json.loads((a/'receipt.json').read_text())
head='f69d71e25ad9833bdfb98c3bb591bd5f72ec0de7'
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
assert git('show','-s','--format=%P',d['checkout']).decode().split()==['aff49a5eb4b7bb111ce949daef66b0b41ddfb274',head]
assert git('rev-parse',head+'^{tree}')==git('rev-parse',d['checkout']+'^{tree}')
assert json.loads(blobs['MacDown2/Packages/MacDownKit/Package.resolved'])['pins']==d['pins'] and len(d['pins'])==24
for path,h in d['generated_sha256'].items():assert sha((a/'fixture'/path).read_bytes())==h,path
fixture={p.removeprefix('.github/hosted-public-focus/'):raw for p,raw in blobs.items() if p.startswith('.github/hosted-public-focus/')}
for path,raw in fixture.items():assert sha(raw)==d['generated_sha256'][path],path
assert set(d['generated_sha256'])==set(fixture)|{'Driver/HostedFocusInputs.swift','HostedPublicFocus.xcodeproj/project.pbxproj','HostedPublicFocus.xcodeproj/project.xcworkspace/contents.xcworkspacedata','HostedPublicFocus.xcodeproj/xcshareddata/xcschemes/HostedPublicFocus.xcscheme'}
original=git('show','6301b0fb914c2846e23c6c418d8b0be17242e6d3:.github/hosted-public-focus/Driver/PublicFocusTests.swift')
assert original==blobs['.github/hosted-public-focus/Driver/PublicFocusTests.swift'],'Every original failed journey assertion remains unchanged'
assert (a/'documents/focus-42347358056.md').read_bytes()==b'- item'
assert d['source_file_sha256']==sha(b'- item')

assert d['passed'] is False and len(d['errors'])==1 and not d.get('cleanup_errors')
assert d['selected_public_method']=='testNormalBundledLicensesAreReadableAndSearchable'
assert d['criteria']=={'benign_control':True,'file_open_acknowledged':True}
for source,row in d['license_oracles'].items():
 assert sha((a/'license-oracles'/pathlib.PurePosixPath(source).name).read_bytes())==row['sha256']==sha(blobs[source])
assert sorted(d['built']['license_resource_sha256'].values())==sorted(row['sha256'] for row in d['license_oracles'].values())
for label,passed,failed,code in [('positive',1,0,0),('focus',0,1,65)]:
 row=d['ui_results'][label];summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(a/(label+'.xcresult'))]));assert summary==row['summary']
 for k,v in {'totalTestCount':1,'passedTests':passed,'failedTests':failed,'skippedTests':0,'expectedFailures':0}.items():assert summary[k]==v
 owned=json.loads((a/(label+'-owned/status.json')).read_text());assert owned==row['owned'] and owned['returncode']==code and not owned['timed_out'] and not owned['cancelled'] and not owned['app_cleanup_requested']
log=(a/'focus.log').read_text();assert 'LicenseNoticesTests.swift:62: error:' in log and log.count(': error:')==1
assert 'continueAfterFailure = false' in blobs['.github/hosted-public-focus/Driver/PublicFocusTests.swift'].decode()
case=blobs['.github/hosted-public-focus/Driver/LicenseNoticesTests.swift'].decode().splitlines();assert case[61].strip()=='XCTAssertTrue(panel.waitForExistence(timeout: 5))'
assert d['ui_results']['focus']['summary']['testFailures'][0]['testIdentifierString']=='PublicFocusTests/testNormalBundledLicensesAreReadableAndSearchable()'
apps=d['applications'];assert [x['operation'] for x in apps]==['launch','inspect','cleanup'] and len({x['pid'] for x in apps})==1 and len({x['birth'] for x in apps})==1 and apps[-1]['terminated']
assert any(w.get('name')=='Find' and w.get('kCGWindowIsOnscreen') for w in apps[1]['windows'])
ax=(root/'f69d-license-first-attachments/07240311-2F56-4DDD-B18E-1EED0C1535BA.txt').read_text()
assert re.search(r"Dialog,.*title: 'Find'",ax) and re.search(r"ComboBox,.*identifier: '_NS:167'.*Keyboard Focused",ax)
assert re.search(r"Button,.*title: 'Next'",ax)
assert 'source-and-build-verification-after' not in [c['label'] for c in d['commands']]
proof={'head':head,'checkout':d['checkout'],'all_complete_source_inputs_verified':len(inputs),'all_pins_verified':24,'actual_generated_inputs_verified':len(d['generated_sha256']),'canonical_mit_bytes':len(blobs['LICENSE']),'canonical_notices_bytes':len(blobs['compliance/generated/THIRD_PARTY_NOTICES.md']),'both_downloaded_oracles_match_canonical_resources_recorded':True,'positive_actual_pass':True,'actual_licence_case_failures':1,'sole_failure_source_line':62,'before_failure_both_complete_actual_text_and_keyboard_copy_assertions_reached_without_failure':True,'actual_find_dialog_visible_and_combo_box_captured':True,'focus_owned':d['ui_results']['focus']['owned'],'identity_bound_failure_cleanup_not_normal_quit':True,'after_source_verification_present':False,'actual_captured_find_ax_sha256':sha(ax.encode()),'scope':'First real licence UI failure is an incorrect Window query: actual Find is Dialog and focused query ComboBox. Canonical full text and Copy checks precede sole failure with continueAfterFailure=false. Find entry/Next/match Copy/close/About remain unexecuted; no whole licence acceptance, after-source proof, normal Quit, rights/VO/signed claim.'}
(root/'f69d-license-first-outcome-independently-verified-failure.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps(proof,indent=2))
