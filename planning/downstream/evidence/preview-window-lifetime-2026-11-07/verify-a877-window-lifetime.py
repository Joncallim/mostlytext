import hashlib,io,json,pathlib,re,subprocess,sys
root=pathlib.Path(__file__).parent;repo=pathlib.Path('/Volumes/Fast SSD/CORTANA-GitHub/worktrees/github/mostlytext-release-source-convergence');head=sys.argv[1];name=sys.argv[2];config=sys.argv[3];pair=sys.argv[4];p=root/name;r=json.loads((p/'receipt.json').read_text());assert r['mutation_pair']==pair and r['configuration']==config and r['testability'] and r['additional_compilation_condition']=='RELEASE_PREVIEW_PROBE'
requests=[head+':'+n for n in sorted(r['source_sha256'])]+[head+':MacDown2/Packages/MacDownKit/Package.resolved'];blobs={};stream=io.BytesIO(subprocess.check_output(['git','cat-file','--batch'],cwd=repo,input=('\n'.join(requests)+'\n').encode()))
for key in requests:
 hdr=stream.readline().split();assert hdr[1]==b'blob',key;blobs[key]=stream.read(int(hdr[2]));assert stream.read(1)==b'\n'
for n,d in r['source_sha256'].items():assert hashlib.sha256(blobs[head+':'+n]).hexdigest()==d,n
tracked=['MacDown2','.github/scripts/verify-preview-grant-probe.py','.github/workflows/preview-grant-probe.yml','.github/scripts/check-preview-parsed-frame.py','.github/scripts/test-preview-grant-tripwire.py','.github/scripts/test-preview-native-architecture.py','.github/scripts/run-preview-grant-probe.py','.github/scripts/run-owned-app-tests.py','.github/scripts/test-run-owned-app-tests.py','.github/scripts/test-preview-diagnostic-host.py']
expected_names=set(subprocess.check_output(['git','ls-tree','-r','--name-only',head,'--',*tracked],cwd=repo,text=True).splitlines());assert expected_names==set(r['source_sha256']), 'Missing/extra tracked input receipt'
assert subprocess.check_output(['git','rev-parse',r['checkout']+'^{tree}'],cwd=repo,text=True).strip()==subprocess.check_output(['git','rev-parse',head+'^{tree}'],cwd=repo,text=True).strip(), 'Checkout tree mismatch'
assert json.loads(blobs[requests[-1]])['pins']==r['pins'];log=(p/'probe.log').read_text();count,suites=(56,18) if config=='Release' else (55,17);assert re.search(f'Test run with {count} tests in {suites} suites passed',log);assert 'recorded an issue at' not in log;assert 'PREVIEW_NETWORK_CONTROL live=true loaded=true deniedRequests=0' in log
if config=='Release':assert 'PREVIEW_RELEASE_PROBE sourceBytes=4194304' in log
for function in ['fileStoreBOMDocumentsRenderAsUTF8WithoutRewritingOriginalBytes', 'nonUTF8HTMLResourcesKeepBOMBytesAndAuthoritativeResponseProtection', 'realSubresourcesKeepTheirMIMETypesAndUnknownHTMLIsNotAnImage', 'canonicallyEquivalentPublishedBytesCannotBorrowTheCurrentGrant', 'pendingPublishedSourceRetiresThePriorLoadAndKeepsPreviewMounted', 'absentParseRetiresItsPriorLoadWithoutRemovingReadableContent', 'originIsReservedBeforeTheCommandTaskCanRun', 'aHeldChoiceRemainsWithItsWindowWhenAnotherWindowBecomesKey', 'sameTextSaveAsRejectsAnOlderHeldFolderChoice', 'rootAwayAndBackCannotReviveAPendingChoice', 'anOlderCancellationCannotClearANewerPendingSelection', 'theRealFolderSheetFinishesWhenItsOriginWindowCloses', 'theRealMarkdownWindowCopiesGrantedImagesAndRevokesThemOnSaveAs', 'theRealHTMLPaneUsesImmutableHandlersAndPreservesSourceRenderedSwitching', 'cancellationAfterBackingAcquisitionCannotPublishAFolderGrant', 'identicalVisibleBlocksFromAnotherParserCannotKeepThePreviousSourceFrame', 'equalRevisionsFromAnotherParserCannotReusePublishedContributions']:assert re.search(r'Test '+re.escape(function)+r'\(\) passed',log),function
initial_identity=json.loads((p/'diagnostics/identity.json').read_text());assert initial_identity['checkout']==r['checkout']
network=json.loads((p/'network.json').read_text());assert not network['denied_requests'] and '/control' in network['paths'] and '/control-webkit' in network['paths'];status=json.loads((p/'diagnostics/status.json').read_text());assert status['returncode']==0 and not status['timed_out'] and not status['cancelled']

assert r['diagnostic_only'] and r['resource_trace_enabled'] and r['execution_architecture']=='arm64' and r['only_active_arch']
selection=(p/'selection-probe.log').read_text();si=json.loads((p/'selection-diagnostics/identity.json').read_text());ss=json.loads((p/'selection-diagnostics/status.json').read_text())
assert si['app_sha256']==initial_identity['app_sha256'] and si['checkout']==head
assert ss['returncode']==0 and not ss['timed_out'] and not ss['cancelled']
assert 'Test run with 1 test in 1 suite passed' in selection and 'recorded an issue at' not in selection
assert 'IMAGE_SELECTION_ORACLE positives=8 negatives=56 capturedBlue=true' in selection
assert 'IMAGE_SELECTION_GATE completed=8' in selection and 'IMAGE_SELECTION_TRACE_ENABLED true' in selection
for n in range(8):
 assert f'IMAGE_SELECTION_GENERATION {n} requests=1 copiedPNG=true' in selection
 assert f'IMAGE_SELECTION_PROVIDER generation={n} request=1 return cancelled=false' in selection
assert 'capturedSRGB=Optional([0.01684189960360527, 0.1983414590358734, 1.0, 1.0])' in selection
assert 'encodedReferenceSRGB=Optional([0.01684189960360527, 0.1983414590358734, 1.0, 1.0])' in selection
assert 'constructor=[0.0, 0.0, 1.0]' in selection
import ast
v=blobs[head+':.github/scripts/verify-preview-grant-probe.py'];fn=next(n for n in ast.parse(v).body if isinstance(n,ast.FunctionDef) and n.name=='verify_native_architecture');namespace={};exec(compile(ast.Module(body=[fn],type_ignores=[]),'reviewed_native_policy','exec'),namespace)
for identity in [initial_identity,si]:namespace['verify_native_architecture'](r,identity,['arm64'])
source=blobs[head+':MacDown2/MacDown2/SecuredMarkdownResourceHost.swift'];records=json.loads((p/'parsed-frame-results.json').read_text())
phases=[]
for row in records:
 phase=row['phase'];mutant=phase.endswith('mutant');raw=source
 if mutant:raw=source.replace(b'revision = document.revision',b'revision = 0') if pair=='revision' else source.replace(b'let retiringContext = slot?.context',b'let retiringContext = current?.context')
 assert row['source_sha256']==hashlib.sha256(raw).hexdigest()
 ident=json.loads((p/('parsed-frame-'+phase+'-diagnostics')/'identity.json').read_text());s=json.loads((p/('parsed-frame-'+phase+'-diagnostics')/'status.json').read_text());t=(p/('parsed-frame-'+phase+'.log')).read_text()
 assert ident['checkout']==head and ident['app_sha256']==row['app_sha256'] and row['original_app_sha256']==initial_identity['app_sha256']
 namespace['verify_native_architecture'](r,ident,['arm64']);assert s['returncode']==row['returncode'] and not s['timed_out'] and not s['cancelled']
 if mutant:assert row['app_sha256']!=initial_identity['app_sha256']
 else:assert row['app_sha256']==initial_identity['app_sha256']
 phases.append({'phase':phase,'status':s,'issues':[l[:12000] for l in t.splitlines() if 'recorded an issue at' in l],'native_app_digest':row['app_sha256']})
summary={'head':head,'full_sources':len(r['source_sha256']),'pins':len(r['pins']),'initial55functions17suites_passed':True,'calibration8positives56negativesAndCapturedBluePassed':True,'all8gatedActualNativePNGGenerationCopiesPassed':True,'selectionOwnedStatus':ss,'phase_results':phases,'scope':'Diagnostic execution and original failures retained. No production correction, original0557 qualification or complete pair inferred.'}

assert len(records)==2 and records[0]['returncode']==65 and records[1]['returncode']==0
assert r['renderer_preference_observer'] is False and r['fixture_window_lifetime_observer'] is True
assert b'.overlayPreferenceValue' not in blobs[head+':MacDown2/MacDown2Tests/SecuredMarkdownMountedTests.swift']
assert 'MOUNTED_COPY_WINDOW_OBSERVER_ACTIVE' in log
stops=[line for line in log.splitlines() if 'MOUNTED_COPY_WINDOW_EVENTS_AT_STOP' in line]
assert len(stops)==3 and all('will-close' not in line for line in stops)
assert all('will-close host=' not in (p/name).read_text() for name in ['probe.log','selection-probe.log','parsed-frame-revision-mutant.log','parsed-frame-revision-restored.log'])
assert 'Test run with 3 tests in 1 suite failed' in (p/'parsed-frame-revision-mutant.log').read_text()
assert 'Test run with 3 tests in 1 suite passed' in (p/'parsed-frame-revision-restored.log').read_text()
summary['three_original_fixture_stop_events_without_observed_prior_close']=stops
summary['scope']='One changed-input historical-source window-lifetime discriminator passes55/17, calibrated8images/56negative controls, expected real revision-mutant failure and restored3/1. Full source/pins/native architecture/owned outcomes verified. No copy failure or unexpected close reproduced; three explicit original-fixture stop events show only observe. Extra observed windows do not all have stop records. Callback registration/timing is itself changed diagnostic input. No causal history, production remediation, original0557 qualification, disappearance pair or final artifact acceptance.'
(root/'a877-window-lifetime-first-outcome-independently-verified.json').write_text(json.dumps(summary,indent=2)+'\n');print({k:v for k,v in summary.items() if not isinstance(v,(dict,list))})
