import hashlib,json,pathlib,re,subprocess,zipfile
root=pathlib.Path(__file__).parent;head='4b6717905aaabb4053f20589ec323905d86dcef6';run=42359122979;repo='/Volumes/Fast SSD/CORTANA-GitHub/mostlytext';archive=root/'4b67-full-ci-full-logs.zip'
def git(*a):return subprocess.check_output(['git',*a],cwd=repo,text=True).strip()
def api(p):return json.loads(subprocess.check_output(['gh','api','repos/Joncallim/mostlytext/'+p],text=True))
r=api('actions/runs/'+str(run));assert r['head_sha']==head and r['status']=='completed' and r['conclusion']=='success'
jobs=api('actions/runs/'+str(run)+'/jobs')['jobs'];assert len(jobs)==2 and all(j['conclusion']=='success' for j in jobs)
optional={'Prepare bounded package crash diagnostics','Collect fresh package test crash reports','Upload bounded package crash diagnostics'}
for job in jobs:
 assert all(s['conclusion']=='success' or (s['name'] in optional and s['conclusion']=='skipped') for s in job['steps'])
z=zipfile.ZipFile(archive);names=z.namelist()
def step(fragment):
 found=[n for n in names if n.startswith('build-and-test/') and fragment in n];assert len(found)==1,(fragment,found);return z.read(found[0]).decode('utf-8-sig')
package=step('Package build + tests');app=step('Run MacDown2Tests');debug=step('13_Build app + CLI.txt');release=step('14_Build app + CLI (Release)');compile=step('Build for testing');metadata=step('Verify compiled document metadata');pins=step('Verify every build used');checkout=step('/2_Run actions_checkout')
assert 'Test run with 3719 tests in 536 suites passed' in package
assert 'Test run with 679 tests in 142 suites passed' in app and 'recorded an issue' not in app and 'Restarting after unexpected' not in app
assert 'currentApplicationDomainFinishesEmptyImportWithoutChangingPreferences() passed' in app
assert 'documentCountsChooseIndependentEnglishPluralForms(text:expected:) with 4 test cases passed' in app
assert debug.count('** BUILD SUCCEEDED **')==2 and release.count('** BUILD SUCCEEDED **')==2
assert '** TEST BUILD SUCCEEDED **' in compile and '** TEST EXECUTE SUCCEEDED **' in app
formatlog=z.read(next(n for n in names if n.startswith('lint/') and 'SwiftFormat (lint)' in n)).decode();lint=z.read(next(n for n in names if n.startswith('lint/') and 'SwiftLint (strict)' in n)).decode()
assert '0/1489 files require formatting' in formatlog and 'Found 0 violations, 0 serious in 1489 files' in lint
owned=root/'4b67-full-ci-artifact'/f'owned-package-test-result-{run}-1';identity=json.loads((owned/'identity.json').read_text());status=json.loads((owned/'status.json').read_text());reports=json.loads((owned/'reports.json').read_text())
assert status=={'returncode':0} and reports==[];assert git('show','-s','--format=%P',identity['checkout']).split()==['ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9',head];assert git('merge-tree','--write-tree','ef93ab2d4fbda72cdd126560ffb19cd7e012a5d9',head).splitlines()[0]==git('rev-parse',identity['checkout']+'^{tree}');assert git('diff','--name-only',head,identity['checkout'],'--','MacDown2','.github/workflows/ci.yml','.github/scripts')=='';assert identity['checkout'] in checkout
record={'head':head,'checkout':identity['checkout'],'source_tree':git('rev-parse',head+'^{tree}'),'actual_tested_tree':git('rev-parse',identity['checkout']+'^{tree}'),'all_product_package_ci_workflow_and_scripts_byte_equal_across_docs_merge':True,'package_functions':3719,'package_suites':536,'app_functions':679,'app_suites':142,'actual_current_domain_journal_regression_passed':True,'actual_english_independent_plural_four_cases_passed':True,'all_four_builds':True,'app_ui_test_bundle_compilation':True,'metadata_catalog_final_pins_steps_passed':True,'formatter_lint_zero':True,'package_owned_returncode':0,'package_owned_checkout_verified':True,'new_owned_crash_reports':0,'zip_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'preexisting_optional_pr535_diagnostics_skipped':sorted(optional),'scope':'Complete normal CI at actual product/orchestration source4b67; original receipts not retargeted to later documentation. No owner/signed/installed/final-artifact acceptance.'}
(root/'4b67-full-ci-independently-verified.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
