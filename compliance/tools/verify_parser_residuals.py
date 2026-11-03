#!/usr/bin/env python3
"""Keep every residual parser position bound to narrow syntax evidence, not rights clearance."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from verify_parser_classification import verify_installed as checked_parent, PACKET as PARENT, INDEX, INDEX_SHA, PARSER_SHA

ROOT = Path(__file__).resolve().parents[2]
PACKET = 'compliance/evidence/parser-residual-positions'
MANIFEST_SHA = 'fa7976169d24c84ed740c1386c0d7ee33d571b472b9e500ddc6879ba40fce0aa'
PARENT_SHA = 'de87447fd7390841f770969dcc9ed44a243f098546086f5cd40cfa3ca0fae63f'
EXPECTED = {'closing-object-delimiter':10, 'constructor-super-forwarding':44,
            'closing-array-delimiter':7, 'uninitialized-var-declaration':10, 'else-if-keyword':15,
            'alternate-block-boundary':3, 'invoked-arrow-header':2, 'wrapper-strict-directive':1,
            'numeric-module-table-header':6, 'static-block-opening':2}
NODE_TYPES = dict(zip(EXPECTED, ['ObjectExpression', 'CallExpression', 'ArrayExpression',
    'VariableDeclaration', 'IfStatement', 'BlockStatement', 'ArrowFunctionExpression',
    'ExpressionStatement', 'VariableDeclaration', 'StaticBlock']))
TOKEN_TYPES = {'closing-object-delimiter':{'}'}, 'constructor-super-forwarding':{'super','...','name',')'},
               'closing-array-delimiter':{']'}, 'uninitialized-var-declaration':{'var','name'},
               'else-if-keyword':{'if'}, 'alternate-block-boundary':{'}'},
               'invoked-arrow-header':{'(','{'}, 'wrapper-strict-directive':{'string'},
               'numeric-module-table-header':{'var','name','{','num'}, 'static-block-opening':{'name'}}


def sha(body):
    return hashlib.sha256(body).hexdigest()


def validate_receipt(data, parent, original):
    fields = {'schema','scope','original_index_sha256','parent_classification_sha256','parser_module_sha256',
              'node','parser','parser_controls','independent_review_required','reviewed_references',
              'remaining_technically_unclassified','categories','positions'}
    expected_identity = {'schema':1, 'scope':'Residual syntax disposition only; all original independent attribution/rights review requirements remain',
        'original_index_sha256':INDEX_SHA, 'parent_classification_sha256':PARENT_SHA,
        'parser_module_sha256':PARSER_SHA, 'node':'v24.16.0', 'parser':'acorn@8.19.0',
        'parser_controls':27, 'independent_review_required':True, 'reviewed_references':100,
        'remaining_technically_unclassified':0}
    if set(data) != fields or any(type(data.get(k)) is not type(v) or data[k] != v for k,v in expected_identity.items()):
        raise ValueError('Residual syntax identity/review boundary changed')
    selected = [row for row in parent['positions'] if row['technical_category'] == 'unclassified']
    entries = data['positions']
    if not isinstance(entries,list) or len(entries) != len(selected) or len(entries) != 100:
        raise ValueError('Complete exact residual row set required')
    counts = Counter()
    for entry, old in zip(entries,selected):
        if (set(entry) != {'original_row_index','original_row_sha256','technical_category','category',
                          'token_type','token_span','token_sha256','node_type','node_span','node_sha256'}
                or any(type(entry.get(k)) is not type(v) or entry[k] != v for k,v in old.items())):
            raise ValueError('Original residual row binding changed')
        row = original['positions'][old['original_row_index']]
        canonical = json.dumps(row,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
        if sha(canonical) != old['original_row_sha256']:
            raise ValueError('Original member/coordinate/outer-reference identity changed')
        category = entry['category']
        if category not in EXPECTED or entry['node_type'] != NODE_TYPES[category] or entry['token_type'] not in TOKEN_TYPES[category]:
            raise ValueError('Unsupported residual structure/token category')
        for key in ['node_span','token_span']:
            span=entry[key]
            if not isinstance(span,list) or len(span)!=2 or any(type(v) is not int for v in span) or not 0 <= span[0] < span[1]:
                raise ValueError('Invalid UTF-16 token/node span')
        if not entry['node_span'][0] <= entry['token_span'][0] < entry['token_span'][1] <= entry['node_span'][1]:
            raise ValueError('Token falls outside supporting syntax node')
        if any(not isinstance(entry[k],str) or not re.fullmatch('[0-9a-f]{64}',entry[k]) for k in ['node_sha256','token_sha256']):
            raise ValueError('Invalid exact token/node digest')
        counts[category] += row['outer_reference_count']
    if (counts != EXPECTED or data['categories'] != EXPECTED
            or any(type(v) is not int for v in data['categories'].values())):
        raise ValueError('Exact residual category/reference totals changed')


def verify_installed(root=ROOT):
    folder=root/PACKET
    try:
        raw=(folder/'manifest.json').read_bytes()
    except FileNotFoundError as error:
        raise ValueError('Pinned residual classification proof missing') from error
    if sha(raw)!=MANIFEST_SHA:
        raise ValueError('Pinned residual classification manifest changed')
    manifest=json.loads(raw)
    for name,digest in manifest['files'].items():
        if '/' in name or name in ('.','..') or sha((folder/name).read_bytes())!=digest:
            raise ValueError('Pinned residual classification evidence changed: '+name)
    checked_parent(root)
    if sha((root/PARENT/'manifest.json').read_bytes())!=manifest['parentManifestSHA256']:
        raise ValueError('First classification packet changed')
    raw_parent=(root/PARENT/'classification.json').read_bytes()
    if sha(raw_parent)!=PARENT_SHA:
        raise ValueError('Original residual selection changed')
    original=json.loads((root/INDEX).read_text())
    selected=[original['positions'][r['original_row_index']] for r in json.loads(raw_parent)['positions']
              if r['technical_category']=='unclassified']
    if any(row['parser_member']!=manifest['sourceMember'] or row['parser_member_sha256']!=manifest['sourceMemberSHA256'] for row in selected):
        raise ValueError('Residual reproduced member binding changed')
    validate_receipt(json.loads((folder/'classification.json').read_text()),json.loads(raw_parent),original)


if __name__=='__main__':
    verify_installed()
    print('Residual parser syntax: all 100 positions classified; independent review still required')
