#!/usr/bin/env python3
"""Extend the existing guarded ordinary-app fixture for one real export UI journey."""
import argparse
import hashlib
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys

PRODUCT_BASELINE = 'df96aa846f70272806ed8845e1eaedbccb27a9b7'
PRODUCT_TREE = '01eadc264d6837e6cbc4fc3ac114437af4121207'

SOURCE = '# NATIVE_EXPORT_CANARY\r\n\r\nA café document with **bold** and `code`.\r\n\r\n| Key | Value |\r\n| --- | --- |\r\n| alpha | beta |\r\n'.encode()
PRIVATE_SOURCE = b'# NATIVE_EXPORT_CANARY\n\nA **bold** paragraph.\n\n- first\n- second\n\n'
EXTRA = ['.github/hosted-export-acceptance', '.github/scripts/prepare-ordinary-export-acceptance.py',
         '.github/scripts/run-ordinary-export-acceptance.py', '.github/scripts/test-ordinary-export-acceptance.py',
         '.github/scripts/verify-placed-pdf-canary.py',
         '.github/workflows/ordinary-export-acceptance.yml']


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def preparation():
    spec=importlib.util.spec_from_file_location('qualified_focus',Path(__file__).with_name('prepare-hosted-public-focus.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


def output(args):return subprocess.check_output(args,text=True,timeout=60).strip()


def capture(root):
    app=root/'app/Build/Products/Release/MacDown2.app'
    control=root/'control/Build/Products/Release'
    bundles=[app,control/'HostedFocusControl.app',control/'HostedFocusDriverTests-Runner.app']
    plans=list((root/'control/Build/Products').glob('*.xctestrun'))
    if len(plans)!=1:raise RuntimeError('Require exact compiled UI execution plan')
    roles={'normal_app_host':root/'normal-app-host','host_facts':root/'host-facts',
           'pdf_validator':root/'validate-export-pdf','actual_ui_plan':plans[0],
           'generated_project':root/'fixture/HostedPublicFocus.xcodeproj/project.pbxproj',
           'actual_build_settings':root/'root-build-settings.json'}
    for bundle in bundles:
        info_path=bundle/'Contents/Info.plist'
        if not info_path.is_file():raise RuntimeError('Missing signed execution bundle')
        info=plistlib.loads(info_path.read_bytes())
        executable=bundle/'Contents/MacOS'/info['CFBundleExecutable']
        if not executable.is_file() or executable.is_symlink():raise RuntimeError('Missing regular actual bundle executable')
        for path in bundle.rglob('*'):
            if path.is_file():roles['bundle:'+bundle.name+'/'+str(path.relative_to(bundle))]=path
    tests=list((control/'HostedFocusDriverTests-Runner.app/Contents/PlugIns').glob('*.xctest/Contents/MacOS/HostedFocusDriverTests'))
    if len(tests)!=1 or not tests[0].is_file():raise RuntimeError('Missing actual compiled export UI test executable')
    result={};total=0;blobs=root/'export-compiled-inputs/blobs';blobs.mkdir(parents=True,exist_ok=True)
    for role,path in roles.items():
        raw=path.read_bytes();total+=len(raw)
        if len(raw)>256*1024*1024 or total>512*1024*1024:raise RuntimeError('Actual compiled input budget exceeded')
        value=hashlib.sha256(raw).hexdigest();blob=blobs/value
        if not blob.exists():
            with blob.open('xb') as stream:stream.write(raw)
        if blob.read_bytes()!=raw:raise RuntimeError('Actual compiled copy differs')
        result[role]={'path':str(path),'bytes':len(raw),'sha256':value,'blob':str(blob.relative_to(root))}
    return result


def validate_settings(rows):
    row=next(x['buildSettings'] for x in rows if x['target']=='MacDown2')
    if row.get('CONFIGURATION')!='Release' or row.get('PRODUCT_BUNDLE_IDENTIFIER')!='app.mostlytext.MostlyText':
        raise RuntimeError('Require actual ordinary Release app settings')
    conditions=row.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS','').split()
    if conditions:raise RuntimeError('Ordinary Release must not add test compilation conditions')
    if row.get('ONLY_ACTIVE_ARCH')!='YES' or 'arm64' not in row.get('ARCHS','').split():
        raise RuntimeError('Require actual hosted ARM build, not an inferred project setting')


def verify_product_tree():
    actual=output(['git','rev-parse','HEAD:MacDown2'])
    if actual!=PRODUCT_TREE:
        raise RuntimeError('Product inputs differ from the bound ordinary Release baseline')
    return actual


def private_fixture():
    base = Path(output(['getconf', 'DARWIN_USER_TEMP_DIR'])).resolve(strict=True)
    if not str(base).startswith('/private/var/folders/') or base.name != 'T':
        raise RuntimeError('Require the real per-user Darwin private temp directory')
    run = os.environ.get('GITHUB_RUN_ID', '')
    if not run.isdecimal():
        raise RuntimeError('Require the hosted run ID for a fresh private fixture')
    directory = base / ('MostlyTextAcceptance-' + run)
    directory.mkdir(mode=0o700)
    source = directory / 'export-canary.md'
    source.write_bytes(PRIVATE_SOURCE)
    return source


def main():
    if sys.flags.optimize:raise RuntimeError('Optimized Python cannot enforce export acceptance')
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('root',type=Path)
    phase=parser.add_mutually_exclusive_group();phase.add_argument('--bind-built',action='store_true')
    phase.add_argument('--admit-execution',action='store_true');phase.add_argument('--verify',action='store_true')
    args=parser.parse_args();root=args.root.resolve();preparation().check_host(root)
    baseline=Path(__file__).with_name('prepare-hosted-public-focus.py')
    receipt=root/'receipt.json'
    actual_tree=verify_product_tree()
    if not (args.bind_built or args.admit_execution or args.verify):
        subprocess.run([sys.executable,str(baseline),str(root)],check=True,timeout=120)
        row=json.loads(receipt.read_bytes());source=Path(row['source_file']);source.write_bytes(SOURCE)
        private_source=private_fixture()
        row['source_file_sha256']=sha(source)
        paths=output(['git','ls-files','--',*EXTRA]).splitlines()
        if not any(x.endswith('ExportPanelTests.swift') for x in paths):raise RuntimeError('Missing tracked actual driver')
        row['source_sha256'].update({p:sha(Path(p)) for p in paths})
        destination=root/'fixture/Driver/ExportPanelTests.swift'
        destination.write_bytes(Path('.github/hosted-export-acceptance/ExportPanelTests.swift').read_bytes())
        row['ordinary_export']={'product_baseline':PRODUCT_BASELINE,
            'product_tree':actual_tree,
            'html':str(source.parent/'ordinary-export.html'),'pdf':str(source.parent/'ordinary-export.pdf'),
            'source':str(source),'source_sha256':sha(source),'diagnostic_only':False,
            'private_source':str(private_source),'private_source_sha256':sha(private_source),
            'private_pdf':str(private_source.with_suffix('.pdf')),
            'scope':'Ordinary Release export UI only; no final RC, whole parity/budgets or in-flight cancellation acceptance'}
        receipt.write_text(json.dumps(row,indent=2)+'\n');return
    subprocess.run([sys.executable,str(baseline),str(root),'--bind-built' if args.bind_built else '--verify'],check=True,timeout=120)
    row=json.loads(receipt.read_bytes())
    if args.bind_built:
        settings=json.loads((root/'root-build-settings.json').read_bytes());validate_settings(settings)
        arch=output(['xcrun','lipo','-archs',row['built']['executable']])
        if arch!='arm64':raise RuntimeError('Actual ordinary app executable is not exactly ARM64')
        row['ordinary_export']['actual_executable_architectures']=arch
        values=row['ordinary_export'];source='// Generated from the guarded fixture before UI compilation.\nenum HostedExportInputs {\n'
        source+=''.join('    static let '+key+' = '+json.dumps(values[key])+'\n' for key in
                        ['source','source_sha256','html','pdf','private_source','private_source_sha256','private_pdf'])
        source=source.replace('let source_sha256','let sourceSHA256').replace('let private_source_sha256','let privateSourceSHA256')+'}\n'
        (root/'fixture/Driver/HostedExportInputs.swift').write_text(source)
        subprocess.run(['xcodegen','generate','--spec',str(root/'fixture/project.yml')],check=True,timeout=60)
        row['generated_sha256']={str(p.relative_to(root/'fixture')):sha(p) for p in (root/'fixture').rglob('*') if p.is_file()}
        row['ordinary_export']['actual_build_settings']=settings
    elif args.admit_execution:
        if 'export_compiled_before' in row:raise RuntimeError('Actual execution was already admitted')
        row['export_compiled_before']=capture(root)
    else:
        if capture(root)!=row['export_compiled_before']:raise RuntimeError('Actual export execution input changed')
    if Path(row['source_file']).read_bytes()!=SOURCE:raise RuntimeError('Actual source bytes changed')
    private=Path(row['ordinary_export']['private_source'])
    if private.read_bytes()!=PRIVATE_SOURCE or sha(private)!=row['ordinary_export']['private_source_sha256']:
        raise RuntimeError('Private Darwin temp source bytes changed')
    receipt.write_text(json.dumps(row,indent=2)+'\n')


if __name__=='__main__':main()
