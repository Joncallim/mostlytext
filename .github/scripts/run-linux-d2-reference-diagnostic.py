#!/usr/bin/env python3
"""One guarded Linux reference observation; no native or production acceptance."""
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import shutil
import subprocess
import sys
import time


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if sys.flags.optimize:raise RuntimeError('Optimized Python cannot enforce the diagnostic guard')
    account=pwd.getpwuid(os.getuid())
    expected=Path('/home/runner/work/_temp/mostlytext-d2-reference-diagnostic')
    if (os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('GITHUB_REPOSITORY')!='Joncallim/mostlytext'
            or os.environ.get('GITHUB_EVENT_NAME')!='workflow_dispatch' or os.environ.get('RUNNER_ENVIRONMENT')!='github-hosted'
            or os.environ.get('GITHUB_REF')!='refs/heads/epic/07-d2-reference-phase-diagnostics'
            or platform.system()!='Linux' or platform.machine()!='x86_64'
            or account.pw_name!='runner' or account.pw_dir!='/home/runner' or os.getuid()!=os.geteuid()
            or Path(os.environ.get('RUNNER_TEMP','/absent')).resolve()!=expected.parent
            or Path.cwd()!=Path(os.environ.get('GITHUB_WORKSPACE','/absent')).resolve()):
        raise RuntimeError('Require exact trusted disposable Linux diagnostic branch before any mutation')
    if expected.exists():raise RuntimeError('Fresh bounded output required')
    expected.mkdir(mode=0o700)
    paths=subprocess.check_output(['git','ls-files','--','.github/quicklook-jscd2-probe',
        '.github/scripts/run-linux-d2-reference-diagnostic.py','.github/workflows/shared-subtree-comparison.yml',
        'MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js',
        'MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/D2-LICENSE.txt',
        'MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/NOTICE.txt',
        'compliance/generated/THIRD_PARTY_NOTICES.md'],text=True).splitlines()
    record={'checkout':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
            'source_sha256':{p:sha(Path(p)) for p in paths},'uid':os.getuid(),'account':account.pw_name,
            'platform':platform.platform(),'diagnostic_only':True,'native_qualification':False}
    fixture=expected/'fixture';shutil.copytree('.github/quicklook-jscd2-probe',fixture)
    resources=Path('MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources')
    for name,source in [('d2-browser.js',resources/'d2-browser.js'),('D2-LICENSE.txt',resources/'D2-LICENSE.txt'),
                        ('D2-NOTICE.txt',resources/'NOTICE.txt'),('THIRD_PARTY_NOTICES.md',Path('compliance/generated/THIRD_PARTY_NOTICES.md'))]:
        shutil.copyfile(source,fixture/'Resources'/name)
    record['copied_sha256']={str(p.relative_to(fixture)):sha(p) for p in fixture.rglob('*') if p.is_file()}
    node=Path(shutil.which('node')).resolve()
    with node.open('rb') as stream:record['node_sha256']=hashlib.file_digest(stream,'sha256').hexdigest()
    record['node_version']=subprocess.check_output([str(node),'--version'],text=True).strip()
    record['command']=[str(node),str(fixture/'reference.cjs'),str(fixture)]
    receipt=expected/'diagnostic-receipt.json';receipt.write_text(json.dumps(record,indent=2)+'\n')
    controls=subprocess.run([str(node),str(fixture/'clone-counterexamples.cjs'),str(fixture/'Resources/host.js')],capture_output=True,timeout=5)
    (expected/'clone-counterexamples.log').write_bytes(controls.stdout+controls.stderr)
    if controls.returncode:raise RuntimeError('Actual clone counterexample harness failed before full reference')
    record['clone_counterexamples']=json.loads(controls.stdout)
    receipt.write_text(json.dumps(record,indent=2)+'\n')
    started=time.monotonic();exit_code=1
    try:
        actual=subprocess.run(record['command'],capture_output=True,timeout=45)
        (expected/'reference-output.log').write_bytes(actual.stdout+actual.stderr)
        record['returncode']=actual.returncode
        if actual.returncode:raise RuntimeError('Actual Linux reference failed; retain its original output')
        value=json.loads(actual.stdout)
        if value.get('real_d2_svg') is not True:raise RuntimeError('Actual real SVG positive absent')
        if record['clone_counterexamples']['passed']!=12 or record['clone_counterexamples']['failed']!=0:
            raise RuntimeError('Actual view kind/byte preservation controls must all pass')
        record['result']=value;exit_code=0
    except subprocess.TimeoutExpired as error:
        (expected/'reference-output.log').write_bytes((error.stdout or b'')+(error.stderr or b''))
        record['timed_out']=True;record['error']=repr(error)
    except BaseException as error:record['error']=repr(error)
    finally:
        record['elapsed_seconds']=time.monotonic()-started
        record['source_unchanged_after']=all(sha(Path(p))==h for p,h in record['source_sha256'].items())
        record['copies_unchanged_after']=all(sha(fixture/p)==h for p,h in record['copied_sha256'].items())
        with node.open('rb') as stream:record['node_unchanged_after']=hashlib.file_digest(stream,'sha256').hexdigest()==record['node_sha256']
        receipt.write_text(json.dumps(record,indent=2)+'\n')
    if not all(record[k] for k in ['source_unchanged_after','copies_unchanged_after','node_unchanged_after']):exit_code=1
    print(json.dumps({k:record[k] for k in ['checkout','diagnostic_only','native_qualification','elapsed_seconds']},indent=2))
    return exit_code


if __name__=='__main__':sys.exit(main())
