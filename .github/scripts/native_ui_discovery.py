"""Read the observed SDK schema; enumeration never means case execution."""
import hashlib
import json
from pathlib import Path
import re

DISCOVERY_SHA256 = 'bc06b3a121021ece81f50834fce2155251c69ea7d8dd5a46793bd785ac14f226'
DISCOVERY_SOURCE = '5307c8386a3f01bbf9dfd4bf2ccf5b9e119b25e5'
DISCOVERY_PATH = 'planning/downstream/evidence/critical-sdk-discovery-2026-11-07/actual-discovered-tests.json'
QUALIFIED_MAIN = '210f46b7f94fdbbf0e8dcc14f2a3cd6c1b306ab3'
PLAN = 'planning/downstream/native-ui-hosted-batches.json'


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON field: ' + key)
        result[key] = value
    return result


def observed_ui_ids(raw, expected):
    value = json.loads(raw, object_pairs_hook=_unique_object)
    if not isinstance(value, dict) or set(value) != {'errors', 'values'} or value['errors'] != []:
        raise ValueError('Unexpected actual SDK response or errors')
    if not isinstance(value['values'], list) or len(value['values']) != 1:
        raise ValueError('Expected one observed test plan')
    plan = value['values'][0]
    if not isinstance(plan, dict) or set(plan) != {'disabledTests', 'enabledTests', 'testPlan'}:
        raise ValueError('Unobserved SDK plan schema')
    if plan['testPlan'] != 'MacDown2' or plan['disabledTests'] != [] or not isinstance(plan['enabledTests'], list):
        raise ValueError('Changed test plan, disabled tests or malformed enabled inventory')
    rows = plan['enabledTests']
    if len(rows) != 717 or any(not isinstance(r, dict) or set(r) != {'identifier'} or
                               not isinstance(r['identifier'], str) for r in rows):
        raise ValueError('Changed or malformed observed inventory')
    identifiers = [r['identifier'] for r in rows]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError('Duplicate discovered identifier')
    if {x.split('/')[0] for x in identifiers} != {'MacDown2Tests', 'MacDown2UITests'}:
        raise ValueError('Unexpected target in actual SDK inventory')
    ui = [x for x in identifiers if x.startswith('MacDown2UITests/')]
    if len(ui) != 38 or any(not re.fullmatch(r'MacDown2UITests/[A-Za-z0-9]+/test[A-Za-z0-9]+\(\)', x) for x in ui):
        raise ValueError('Unexpected UI identifier or suffix')
    actual = sorted(x[:-2] for x in ui)
    if len(expected) != 38 or len(set(expected)) != 38 or actual != sorted(expected):
        raise ValueError('Discovered IDs differ from complete source inventory')
    return actual


def selected_batch(root, batch):
    root = Path(root)
    plan = json.loads((root / PLAN).read_text(), object_pairs_hook=_unique_object)
    expected_keys = {'schemaVersion', 'qualifiedDiscoverySource', 'qualifiedMain', 'actualDiscoveryPath',
                     'actualDiscoverySHA256', 'scope', 'batches'}
    if set(plan) != expected_keys or type(plan['schemaVersion']) is not int or plan['schemaVersion'] != 1:
        raise ValueError('Unknown fixed batch plan')
    if (plan['qualifiedMain'] != QUALIFIED_MAIN or plan['actualDiscoverySHA256'] != DISCOVERY_SHA256
            or plan['qualifiedDiscoverySource'] != DISCOVERY_SOURCE or plan['actualDiscoveryPath'] != DISCOVERY_PATH):
        raise ValueError('Changed qualified calibration')
    path = Path(plan['actualDiscoveryPath'])
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Calibration path must remain in this repository')
    raw = (root / path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != DISCOVERY_SHA256:
        raise ValueError('Actual calibration bytes changed')
    manifest = json.loads((root / 'planning/downstream/native-ui-required-cases.json').read_text())
    ids = observed_ui_ids(raw, [row['id'] for row in manifest['cases']])
    groups = plan['batches']
    if not isinstance(groups, list) or len(groups) != 10:
        raise ValueError('Expected ten fixed bounded batches')
    for index, group in enumerate(groups):
        if set(group) != {'id', 'cases'} or group['id'] != f'B{index + 1:02d}' or group['cases'] != ids[index * 4:index * 4 + 4]:
            raise ValueError('A fixed batch is missing, duplicated, reordered or retargeted')
    matching = [row for row in groups if row['id'] == batch]
    if len(matching) != 1:
        raise ValueError('Unknown fixed batch selection')
    return {'batch': batch, 'cases': matching[0]['cases'], 'all_discovered_ui_ids': ids,
            'actual_discovery_sha256': DISCOVERY_SHA256, 'qualified_main': QUALIFIED_MAIN,
            'scope': 'Original ordinary Debug engineering cases; not six extra/repeated/final/protected/signed acceptance'}
