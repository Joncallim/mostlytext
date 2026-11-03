#!/usr/bin/env python3
"""Preserve a syntax-only disposition for every original parser review position."""
from collections import Counter
import hashlib
import json
from pathlib import Path

from verify_parser_reproduction import verify_installed as checked_reproduction, PACKET as REPRODUCTION

ROOT = Path(__file__).resolve().parents[2]
PACKET = 'compliance/evidence/parser-position-classification'
MANIFEST_SHA = '29d3fee42fb7148db29920bde189a455fc07bc53727191ffbe9ae80ecbf084ab'
INDEX = 'compliance/evidence/esbuild-parser-runtime/review-positions.json'
INDEX_SHA = '4137239965a49864f71dc3ecbce8dfc04833731c0e92a55cd2dd44b6a9958ec3'
PARSER_SHA = '76254fc76529713b4dfd2532972d17a991ffd9aafeebb1f977445b5506b9fb0b'
EXPECTED = {'import-declaration': 346, 'namespace-export-bindings': 1647,
            'static-name-retention-call': 524, 'syntax-only-line': 911, 'unclassified': 100}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def validate_receipt(data, original):
    fields = {'schema', 'scope', 'original_index_sha256', 'parser', 'parser_module_sha256',
              'node', 'parser_controls', 'independent_review_required', 'total_references',
              'categories', 'positions'}
    if (set(data) != fields or type(data.get('schema')) is not int or data['schema'] != 1
            or data.get('original_index_sha256') != INDEX_SHA
            or data.get('parser') != 'acorn@8.19.0' or data.get('parser_module_sha256') != PARSER_SHA
            or data.get('node') != 'v24.16.0' or type(data.get('parser_controls')) is not int
            or data['parser_controls'] != 11 or data.get('independent_review_required') is not True
            or data.get('scope') != 'Syntax classification only; all original positions retain independent review requirements'):
        raise ValueError('Syntax-only classification identity/review boundary changed')
    rows = data.get('positions')
    required = [(i, row) for i, row in enumerate(original['positions'])
                if row['classification'] == 'requires-independent-review']
    if not isinstance(rows, list) or len(rows) != len(required) or len(rows) != 2597:
        raise ValueError('Complete original classification row set required')
    counts = Counter()
    for entry, (index, row) in zip(rows, required):
        canonical = json.dumps(row, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
        if (set(entry) != {'original_row_index', 'original_row_sha256', 'technical_category'}
                or type(entry['original_row_index']) is not int or entry['original_row_index'] != index
                or entry['original_row_sha256'] != sha(canonical)):
            raise ValueError('Original member/coordinate/reference binding changed')
        category = entry['technical_category']
        if category not in EXPECTED:
            raise ValueError('Unsupported technical classification')
        counts[category] += row['outer_reference_count']
    if (counts != EXPECTED or data.get('categories') != EXPECTED
            or any(type(v) is not int for v in data['categories'].values())
            or type(data.get('total_references')) is not int or data['total_references'] != 3528
            or sum(counts.values()) != original['remaining_review_required_references']):
        raise ValueError('Reviewed technical classification totals changed')


def verify_installed(root=ROOT):
    folder = root / PACKET
    try:
        raw = (folder / 'manifest.json').read_bytes()
    except FileNotFoundError as error:
        raise ValueError('Pinned parser classification proof missing') from error
    if sha(raw) != MANIFEST_SHA:
        raise ValueError('Pinned parser classification manifest changed')
    manifest = json.loads(raw)
    for name, digest in manifest['files'].items():
        if '/' in name or name in ('.', '..') or sha((folder / name).read_bytes()) != digest:
            raise ValueError('Pinned parser classification input changed: ' + name)
    checked_reproduction(root)
    if sha((root / REPRODUCTION / 'manifest.json').read_bytes()) != manifest['reproductionManifestSHA256']:
        raise ValueError('Reproduced parser binding changed')
    raw_index = (root / INDEX).read_bytes()
    if sha(raw_index) != INDEX_SHA or manifest['originalIndexSHA256'] != INDEX_SHA:
        raise ValueError('Original parser position index changed')
    original = json.loads(raw_index)
    rebuilt = {row['member']: row['publishedSHA256'] for row in
               json.loads((root / REPRODUCTION / 'reproduction.json').read_text())['members']}
    if any(rebuilt.get(row['parser_member']) != row['parser_member_sha256'] for row in original['positions']):
        raise ValueError('Position index differs from reproduced parser members')
    validate_receipt(json.loads((folder / 'classification.json').read_text()), original)


if __name__ == '__main__':
    verify_installed()
    print('Parser syntax classification: 3428 classified, 100 unclassified; independent review still required')
