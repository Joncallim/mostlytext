#!/usr/bin/env python3
"""Assemble a deterministic, local D2 source-review package; never publish it."""

import argparse
import gzip
import hashlib
import io
import json
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

PINNED_BASE_SHA = '07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02'
EXTRA_INPUTS = {
    'elkjs-0.8.2-source.tar.gz': ('upstream/elkjs-0.8.2-source.tar.gz', 'b711d4b94005ae4a8deeeec5ccb8e3eab1ef9017991e613ce9a93ccd4453af10'),
    'elk-java-v0.8.1-source.tar.gz': ('upstream/elk-java-v0.8.1-source.tar.gz', '248af2867977e08eb9d91ebb90fbb7b0a1b71f4e8ec020bfc04fe81e44f5dcdd'),
    'google-brotli-v1.1.0-source.tar.gz': ('upstream/google-brotli-v1.1.0-source.tar.gz', 'e720a6ca29428b803f4ad165371771f5398faba397edf6778837a18599ea13ff'),
    'google-brotli-v1.1.0-git-snapshot.tar.gz': ('upstream/google-brotli-v1.1.0-git-snapshot.tar.gz', 'fa3b92d2df91db94a94edd885cba1d1833e642854fe45f0e6490306a5c00bc7a'),
    'google-brotli-3efb-git-snapshot.tar.gz': ('upstream/google-brotli-3efb-git-snapshot.tar.gz', '833366021ae552ceb40a14f1c71619d2af7a5c7765472882434b5094ff811536'),
    'liberation-fonts-ttf-2.00.5.tar.gz': ('upstream/liberation-fonts-ttf-2.00.5.tar.gz', 'f14ff0a0be87b5aeb672e669363b5a699db76feb1144b06798261c0fdcd2b24d'),
    'go1.24.6.darwin-arm64.tar.gz': ('build-inputs/go1.24.6.darwin-arm64.tar.gz', '4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a'),
    'terrastruct-ci-2594100a-source.tar.gz': ('build-inputs/terrastruct-ci-2594100a-source.tar.gz', 'a2129160358307bc8c08049c78dd47767c0528f9370fb8b0704d607eeeb94d3b'),
    'LiberationMono-Regular-2.00.5.woff': ('derived/LiberationMono-Regular-2.00.5.woff', '5b995acac71be5c793f11417f57f1af41bd7ff312248eb13ea04b6cf15311a71'),
    'LiberationMono-Regular-2.00.5.ttf': ('source/LiberationMono-Regular-2.00.5.ttf', '816a2a46416a2d3550b401ff8d0c084ba7e8138782f7057b1e537446012f769a'),
}
REPO_FILES = {
    'compliance/evidence/d2-font-replacement/README.md': 'evidence/d2-font-replacement.txt',
    'compliance/evidence/d2-font-replacement/chroma-liberation-mono.patch': 'patches/chroma-liberation-mono.patch',
    'compliance/evidence/d2-font-replacement/font-conversion.json': 'evidence/font-conversion.json',
    'compliance/evidence/d2-font-replacement/browser-payload-replacement.json': 'evidence/browser-payload-replacement.json',
    'compliance/evidence/d2-font-replacement/build-replay.json': 'evidence/build-replay.json',
    'compliance/evidence/d2-browser-nested-inputs/reproduction.json': 'evidence/d2-browser-nested-inputs.json',
    'compliance/evidence/d2-browser-nested-inputs/README.md': 'evidence/d2-browser-nested-inputs.txt',
    'compliance/evidence/d2-go-js-runtime-review/README.md': 'evidence/d2-go-js-runtime-review/README.md',
    'compliance/evidence/d2-go-js-runtime-review/extract_inputs.py': 'evidence/d2-go-js-runtime-review/extract_inputs.py',
    'compliance/evidence/d2-go-js-runtime-review/compare-go-runtime.js': 'evidence/d2-go-js-runtime-review/compare-go-runtime.js',
    'compliance/evidence/d2-go-js-runtime-review/go-runtime-ast-report.json': 'evidence/d2-go-js-runtime-review/go-runtime-ast-report.json',
    'compliance/evidence/d2-go-js-runtime-review/js-tokenizer/package.json': 'evidence/d2-go-js-runtime-review/js-tokenizer/package.json',
    'compliance/evidence/d2-go-js-runtime-review/js-tokenizer/package-lock.json': 'evidence/d2-go-js-runtime-review/js-tokenizer/package-lock.json',
    'compliance/evidence/d2-js-brotli-source/README.md': 'evidence/d2-js-brotli-source/README.md',
    'compliance/evidence/d2-js-brotli-source/extract_inputs.py': 'evidence/d2-js-brotli-source/extract_inputs.py',
    'compliance/evidence/d2-js-brotli-source/compare-brotli-source.js': 'evidence/d2-js-brotli-source/compare-brotli-source.js',
    'compliance/evidence/d2-js-brotli-source/brotli-ast-report.json': 'evidence/d2-js-brotli-source/brotli-ast-report.json',
    'compliance/tools/convert_lossless_woff.py': 'build/convert_lossless_woff.py',
    'compliance/tools/seed_d2_module_proxy.py': 'build/seed_d2_module_proxy.py',
    'compliance/tools/replace_d2_wasm_payload.py': 'build/replace_d2_wasm_payload.py',
    'compliance/tools/prepare_google_brotli_snapshot.py': 'build/prepare_google_brotli_snapshot.py',
    'compliance/tools/prepare_google_brotli_3efb_snapshot.py': 'build/prepare_google_brotli_3efb_snapshot.py',
    'compliance/generated/THIRD_PARTY_NOTICES.md': 'distribution-snapshot/THIRD_PARTY_NOTICES.md',
    'compliance/generated/sbom.cdx.json': 'distribution-snapshot/sbom.cdx.json',
    'MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/NOTICE.txt': 'notices/NOTICE.txt',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_members(base):
    result = {}
    with tarfile.open(base, 'r:gz') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if (not member.isfile() or member.name.startswith('/') or '..' in path.parts
                    or member.name in result):
                raise ValueError('unsafe base archive member')
            destination = 'original-review/' + member.name
            if destination in result:
                raise ValueError('prefixed base archive member collision')
            result[destination] = archive.extractfile(member).read()
    return result


def members(root, inputs, base, publisher_browser):
    if sha(base.read_bytes()) != PINNED_BASE_SHA:
        raise ValueError('D2 base review archive changed')
    subprocess.run(['python3', str(root / 'compliance/tools/verify_d2_offer.py'), str(base),
                    '--shipped', str(publisher_browser)],
                   check=True, stdout=subprocess.DEVNULL)
    result = read_members(base)
    for name, (destination, expected) in EXTRA_INPUTS.items():
        data = (inputs / name).read_bytes()
        if sha(data) != expected:
            raise ValueError(f'{name}: input hash changed')
        if name == 'google-brotli-v1.1.0-git-snapshot.tar.gz':
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as source:
                present = {member.name for member in source if member.isfile()}
            required = {'brotli-v1.1.0-git/LICENSE', 'brotli-v1.1.0-git/js/decode.ts',
                        'brotli-v1.1.0-git/js/decode.js', 'brotli-v1.1.0-git/js/decode.min.js'}
            if not required <= present:
                raise ValueError('Brotli Git snapshot does not include the JavaScript preferred source')
        if name == 'google-brotli-3efb-git-snapshot.tar.gz':
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as source:
                present = {member.name for member in source}
            required = {'brotli-3efb30f-git/LICENSE', 'brotli-3efb30f-git/js/decode.ts',
                        'brotli-3efb30f-git/js/decode.js', 'brotli-3efb30f-git/js/decode.min.js'}
            if len(present) != 377 or not required <= present:
                raise ValueError('June 2025 Brotli Git snapshot is incomplete')
        result[destination] = data
    for source, destination in REPO_FILES.items():
        result[destination] = (root / source).read_bytes()
    runtime_path = 'evidence/d2-go-js-runtime-review/'
    runtime_report = json.loads(result[runtime_path + 'go-runtime-ast-report.json'])
    runtime_lock = json.loads(result[runtime_path + 'js-tokenizer/package-lock.json'])
    parser = runtime_lock['packages']['node_modules/acorn']
    if (parser['version'] != runtime_report['parserVersion']
            or parser['integrity'] != runtime_report['parserNpmIntegrity']
            or not runtime_report['normalizedPropertyKeyAstEqual']):
        raise ValueError('Go runtime parser/report binding changed')
    for archive_name, member_name, key in (
        ('original-review/upstream/d2-source-581c9109.tar.gz',
         'd2-581c91096b62d644fb5168313142c836b7e68e74/d2js/js/wasm/wasm_exec.js', 'd2'),
        ('build-inputs/go1.24.6.darwin-arm64.tar.gz', 'go/lib/wasm/wasm_exec.js', 'go'),
    ):
        with tarfile.open(fileobj=io.BytesIO(result[archive_name]), mode='r:gz') as archive:
            member = archive.getmember(member_name)
            if not member.isfile() or member.size > 32768:
                raise ValueError('Go runtime input is not a bounded regular file')
            body = archive.extractfile(member).read()
        if len(body) != runtime_report[key]['bytes'] or sha(body) != runtime_report[key]['sha256']:
            raise ValueError('Go runtime source does not match technical comparison')
    decoder_report = json.loads(result['evidence/d2-js-brotli-source/brotli-ast-report.json'])
    if (decoder_report['parserVersion'] != parser['version']
            or decoder_report['parserNpmIntegrity'] != parser['integrity']
            or not decoder_report['astEqual']):
        raise ValueError('Brotli decoder parser/report binding changed')
    for archive_name, member_name, key in (
        ('original-review/upstream/d2-source-581c9109.tar.gz',
         'd2-581c91096b62d644fb5168313142c836b7e68e74/d2js/js/vendor/decode.min.js', 'd2'),
        ('upstream/google-brotli-3efb-git-snapshot.tar.gz',
         'brotli-3efb30f-git/js/decode.min.js', 'google'),
    ):
        with tarfile.open(fileobj=io.BytesIO(result[archive_name]), mode='r:gz') as archive:
            member = archive.getmember(member_name)
            if not member.isfile() or member.size > 262144:
                raise ValueError('Brotli decoder is not a bounded regular file')
            body = archive.extractfile(member).read()
        if len(body) != decoder_report[key]['bytes'] or sha(body) != decoder_report[key]['sha256']:
            raise ValueError('Brotli decoder source does not match technical comparison')
    report = json.loads(result['evidence/browser-payload-replacement.json'])
    current_resource = root / 'MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js'
    if sha(current_resource.read_bytes()) != report['output_browser_sha256']:
        raise ValueError('current D2 browser resource does not match source-review build report')
    result['README.txt'] = (
        'MostlyText D2 local source-review package, 14 November 2026.\n'
        'This package contains the pinned D2 source, npm input, 16 Go module ZIPs,\n'
        'D2 export patch, build helper, Go toolchain/source, official font source,\n'
        'lossless WOFF conversion and Chroma patch, ELK/elkjs and Google Brotli\n'
        'reference source, including full v1.1.0 and June 2025 Git trees, notices,\n'
        'a reproducible Go JavaScript runtime AST comparison,\n'
        'a reproducible Brotli decoder AST comparison,\n'
        'and exact resource/build digests. The GitHub export tar is preserved\n'
        'separately: its export rules omit js/ and it is not sufficient alone.\n'
        'ELK Java/GWT historical correspondence, Brotli historical copy, Go JS\n'
        'runtime historical copy/behavior and further per-file rights review remain open.\n'
        'This is not an approved complete corresponding-source offer and is not\n'
        'authorized for public upload. No MostlyText app binary is included.\n'
        'Rebuild: unpack upstream D2 source and original-review module ZIPs;\n'
        'apply patches/chroma-liberation-mono.patch to Chroma v2.14.0; place it\n'
        'beside the D2 source as chroma-v2.14.0 and use relative go.mod replace\n'
        'github.com/alecthomas/chroma/v2 => ../chroma-v2.14.0.\n'
        'Run build/seed_d2_module_proxy.py\n'
        'on this archive into an empty directory, then compile ./d2js with Go 1.24.6,\n'
        'GOOS=js GOARCH=wasm, CGO_ENABLED=0, GOPROXY=file://<absolute proxy URI>,\n'
        'GOMODCACHE=<empty directory>, GOSUMDB=off, GOENV=off, GOTOOLCHAIN=local,\n'
        'GOWORK=off, -mod=readonly, -trimpath and linker flags\n'
        '-s -w -X oss.terrastruct.com/d2/d2js/d2wasm.jsVersion=0.1.33\n'
        '-X oss.terrastruct.com/d2/lib/version.Version='
        'v0.6.10-0.20250817190149-581c91096b62+dirty. This version string\n'
        'matches the pinned publisher metadata; it is an explicit controlled\n'
        'linker input and does not reproduce the publisher Git checkout.\n'
        'The exact new output digest and Node Brotli version are in\n'
        'evidence/browser-payload-replacement.json. The historical publisher\n'
        'optimizer was not reproduced.\n'
    ).encode()
    for name, body in result.items():
        if name.endswith(('.txt', '.md', '.json', '.py', '.patch')) and not name.startswith('original-review/'):
            if b'/Users/' in body or b'/Volumes/' in body:
                raise ValueError(f'private machine path in source-review text: {name}')
    return result


def encode(path, bodies):
    entries = [{'path': name, 'sha256': sha(data), 'size': len(data)} for name, data in sorted(bodies.items())]
    report = json.loads(bodies['evidence/browser-payload-replacement.json'])
    manifest = json.dumps({'schema': 1, 'status': 'local-review-only; source and rights approval pending',
                           'distribution_resource_sha256': report['output_browser_sha256'],
                           'replacement_wasm_sha256': report['replacement_wasm_sha256'],
                           'official_ttf_sha256': '816a2a46416a2d3550b401ff8d0c084ba7e8138782f7057b1e537446012f769a',
                           'files': entries}, indent=2).encode() + b'\n'
    contents = dict(bodies, **{'manifest.json': manifest})
    with path.open('wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', mtime=0, filename='') as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.USTAR_FORMAT) as out:
            for name, data in sorted(contents.items()):
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime, info.uid, info.gid = len(data), 0o644, 0, 0, 0
                out.addfile(info, io.BytesIO(data))
    with tarfile.open(path, 'r:gz') as archive:
        found = {member.name: archive.extractfile(member).read() for member in archive}
    if found != contents:
        raise ValueError('new archive does not match selected inputs')
    return {'archive_sha256': sha(path.read_bytes()), 'archive_bytes': path.stat().st_size,
            'files': len(entries), 'manifest_sha256': sha(manifest)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--publisher-browser', type=Path, required=True,
                        help='The original reviewed resource before the new WASM payload')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('refusing to overwrite an existing source package')
    print(json.dumps(encode(args.output, members(args.root, args.inputs, args.base,
                                                 args.publisher_browser)), indent=2))


if __name__ == '__main__':
    main()
