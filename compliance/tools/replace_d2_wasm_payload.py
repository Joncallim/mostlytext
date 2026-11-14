#!/usr/bin/env python3
"""Replace only the reviewed D2 browser bundle's Brotli WASM literal.

The tool refuses an unexpected publisher bundle or WASM. The historical npm
archive and one-statement export patch remain separate review inputs.
"""

import argparse
import base64
import hashlib
import json
import re
import subprocess
from pathlib import Path

PUBLISHER_BROWSER_SHA = '991a44779c91b74cbdf141228a6ba34592fe9b708fe19c221eba9ef4a7cfe33e'
PUBLISHER_COMPRESSED_SHA = 'c460c8f8fcbf641b223d8bfbf2f1ced53fd2dddc9b620d8bdf73f70f9dfc8004'
PUBLISHER_WASM_SHA = '7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def node_brotli(data, decompress=False):
    method = 'brotliDecompressSync' if decompress else 'brotliCompressSync'
    return subprocess.run(['node', '-e', f'process.stdout.write(require("node:zlib").{method}(require("node:fs").readFileSync(0)))'],
                          input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def replace(browser, wasm):
    if sha(browser) != PUBLISHER_BROWSER_SHA:
        raise ValueError('expected the reviewed publisher bundle with only the export patch')
    if wasm[:4] != b'\0asm':
        raise ValueError('replacement is not WebAssembly')
    matches = list(re.finditer(rb'"([A-Za-z0-9+/=]{100000,})"', browser))
    matches = [m for m in matches if sha(base64.b64decode(m.group(1))) == PUBLISHER_COMPRESSED_SHA]
    if len(matches) != 1:
        raise ValueError('expected exactly one pinned Brotli WASM literal')
    match = matches[0]
    old_compressed = base64.b64decode(match.group(1))
    if sha(node_brotli(old_compressed, True)) != PUBLISHER_WASM_SHA:
        raise ValueError('compressed literal does not decode to publisher WASM')
    new_compressed = node_brotli(wasm)
    if node_brotli(new_compressed, True) != wasm:
        raise AssertionError('new WASM Brotli round-trip failed')
    out = browser[:match.start(1)] + base64.b64encode(new_compressed) + browser[match.end(1):]
    return out, {'publisher_browser_sha256': sha(browser),
                 'publisher_wasm_sha256': PUBLISHER_WASM_SHA,
                 'replacement_wasm_sha256': sha(wasm),
                 'replacement_wasm_bytes': len(wasm),
                 'replacement_brotli_sha256': sha(new_compressed),
                 'replacement_brotli_bytes': len(new_compressed),
                 'output_browser_sha256': sha(out),
                 'output_browser_bytes': len(out),
                 'literal_offset': match.start(1),
                 'node_version': subprocess.check_output(['node', '--version'], text=True).strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', type=Path, required=True)
    parser.add_argument('--wasm', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    out, report = replace(args.browser.read_bytes(), args.wasm.read_bytes())
    args.output.write_bytes(out)
    args.report.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
