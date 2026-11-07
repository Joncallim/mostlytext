#!/usr/bin/env python3
"""Mutate the actual retained SDK output, never an invented inventory schema."""
import copy
import json
from pathlib import Path
import unittest
from native_ui_discovery import observed_ui_ids, selected_batch

ROOT = Path(__file__).resolve().parents[2]
RAW = (ROOT / 'planning/downstream/evidence/critical-sdk-discovery-2026-11-07/actual-discovered-tests.json').read_bytes()
EXPECTED = [r['id'] for r in json.loads((ROOT / 'planning/downstream/native-ui-required-cases.json').read_text())['cases']]


class ActualDiscoveryControls(unittest.TestCase):
    def test_actual_raw_sdk_and_all_fixed_partitions_match_exact38(self):
        self.assertEqual(observed_ui_ids(RAW, EXPECTED), sorted(EXPECTED))
        groups = [selected_batch(ROOT, f'B{i:02d}')['cases'] for i in range(1, 11)]
        self.assertEqual([x for group in groups for x in group], sorted(EXPECTED))
        self.assertEqual([len(x) for x in groups], [4] * 9 + [2])

    def refuse(self, mutate):
        value = json.loads(RAW)
        mutate(value)
        with self.assertRaises(ValueError):
            observed_ui_ids(json.dumps(value), EXPECTED)
        self.assertEqual(observed_ui_ids(RAW, EXPECTED), sorted(EXPECTED))

    def test_actual_missing_duplicate_extra_and_disabled_ui_records_refuse(self):
        def missing(v):
            v['values'][0]['enabledTests'] = [x for x in v['values'][0]['enabledTests'] if x['identifier'] != EXPECTED[0] + '()']
        def duplicate(v):
            v['values'][0]['enabledTests'].append({'identifier': EXPECTED[0] + '()'})
        def extra(v):
            v['values'][0]['enabledTests'].append({'identifier': 'MacDown2UITests/Unknown/testUnknown()'})
        def disabled(v):
            v['values'][0]['disabledTests'].append({'identifier': EXPECTED[0] + '()'})
        for mutation in [missing, duplicate, extra, disabled]:
            with self.subTest(mutation=mutation.__name__):
                self.refuse(mutation)

    def test_real_ui_identifier_changed_suffix_or_target_refuses(self):
        def change(v, replacement):
            row = next(x for x in v['values'][0]['enabledTests'] if x['identifier'].startswith('MacDown2UITests/'))
            row['identifier'] = replacement
        for replacement in [EXPECTED[0], EXPECTED[0] + '(argument)', EXPECTED[0] + '()trailing', 'OtherTests/Unknown/testUnknown()']:
            with self.subTest(replacement=replacement):
                self.refuse(lambda v: change(v, replacement))

    def test_actual_errors_unknown_schema_and_duplicate_json_fields_refuse(self):
        self.refuse(lambda v: v['errors'].append('Actual SDK error control'))
        self.refuse(lambda v: v.update(unknown=[]))
        self.refuse(lambda v: v['values'][0].update(unknown=[]))
        with self.assertRaises(ValueError):
            observed_ui_ids('{"errors":[],"errors":[],"values":[]}', EXPECTED)

    def test_actual_fixed_plan_cannot_omit_duplicate_reorder_or_retarget_a_case(self):
        import tempfile
        from native_ui_discovery import PLAN, DISCOVERY_PATH
        original = json.loads((ROOT / PLAN).read_text())
        with tempfile.TemporaryDirectory(prefix='mostlytext-fixed-batch-controls-') as temporary:
            root = Path(temporary)
            (root / DISCOVERY_PATH).parent.mkdir(parents=True)
            (root / DISCOVERY_PATH).write_bytes(RAW)
            manifest = root / 'planning/downstream/native-ui-required-cases.json'
            manifest.write_bytes((ROOT / 'planning/downstream/native-ui-required-cases.json').read_bytes())
            for mutation in ['missing-case', 'duplicate-case', 'reordered', 'wrong-source']:
                plan = copy.deepcopy(original)
                if mutation == 'missing-case': plan['batches'][0]['cases'].pop()
                if mutation == 'duplicate-case': plan['batches'][0]['cases'][1] = plan['batches'][0]['cases'][0]
                if mutation == 'reordered': plan['batches'][0]['cases'].reverse()
                if mutation == 'wrong-source': plan['qualifiedDiscoverySource'] = '0' * 40
                (root / PLAN).write_text(json.dumps(plan))
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    selected_batch(root, 'B01')
            (root / PLAN).write_text(json.dumps(original))
            self.assertEqual(selected_batch(root, 'B01')['cases'], sorted(EXPECTED)[:4])

    def test_wrong_expected_set_or_unknown_batch_is_not_a_partial_pass(self):
        for expected in [EXPECTED[:-1], EXPECTED + [EXPECTED[0]], ['Unknown'] * 38]:
            with self.assertRaises(ValueError):
                observed_ui_ids(RAW, expected)
        for key in ['B00', 'B11', EXPECTED[0], '../B01']:
            with self.assertRaises(ValueError):
                selected_batch(ROOT, key)


if __name__ == '__main__':
    unittest.main()
