#!/usr/bin/env python3
"""Source-only adversarial inventory controls; no application or native execution."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("required_cases", Path(__file__).with_name("check-native-ui-required-cases.py"))
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)
MANIFEST = json.loads((ROOT / "planning/downstream/native-ui-required-cases.json").read_text())


class RequiredSourceCasesTests(unittest.TestCase):
    def test_current_source_snapshot_is_not_a_native_pass(self):
        result = CHECKER.validate(ROOT, MANIFEST)
        self.assertEqual(result["declared_source_cases"], 38)
        self.assertIn("Source declarations only", result["scope"])

    def test_duplicate_case_refused(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["cases"].append(manifest["cases"][0])
        with self.assertRaisesRegex(ValueError, "duplicate"): CHECKER.validate(ROOT, manifest)

    def test_dropped_frozen_behavior_refused(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["originalRequiredIDs"].pop()
        with self.assertRaisesRegex(ValueError, "Original required"): CHECKER.validate(ROOT, manifest)

    def test_deleted_case_refused(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["cases"].pop()
        with self.assertRaisesRegex(ValueError, "Source case inventory"): CHECKER.validate(ROOT, manifest)

    def test_changed_source_digest_refused(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["sources"][next(iter(manifest["sources"]))] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Source bytes changed"): CHECKER.validate(ROOT, manifest)

    def test_result_field_cannot_fake_native_acceptance(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["passed"] = True
        with self.assertRaisesRegex(ValueError, "result-like"): CHECKER.validate(ROOT, manifest)

    def test_absent_source_journey_cannot_disappear(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["additionalRequiredBehaviors"].pop()
        with self.assertRaisesRegex(ValueError, "cannot disappear"): CHECKER.validate(ROOT, manifest)

    def test_rename_needs_a_traceable_replacement_even_after_all_local_bindings_refresh(self):
        manifest = copy.deepcopy(MANIFEST)
        case = manifest["cases"][0]
        old = case["id"]
        new = old + "Renamed"
        with tempfile.TemporaryDirectory(prefix="mostlytext-source-case-control-") as temporary:
            root = Path(temporary)
            shutil.copytree(ROOT / "MacDown2/MacDown2UITests", root / "MacDown2/MacDown2UITests")
            path = root / case["source"]
            path.write_text(path.read_text().replace("func " + old.split("/")[-1] + "(", "func " + new.split("/")[-1] + "("))
            case["id"] = new
            manifest["sources"][case["source"]] = hashlib.sha256(path.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, "without its traceable replacement"): CHECKER.validate(root, manifest)
            manifest["replacements"] = [{"original": old, "replacement": new, "reason": "Synthetic fixture-only rename control; not an adopted test change.", "evidenceReference": "test-native-ui-required-cases.py synthetic control"}]
            self.assertEqual(CHECKER.validate(root, manifest)["traceable_replacements"], 1)

    def test_duplicate_json_key_refused(self):
        with self.assertRaisesRegex(ValueError, "Duplicate manifest key"):
            json.loads('{"schemaVersion":1,"schemaVersion":1}', object_pairs_hook=CHECKER.reject_duplicates)


if __name__ == "__main__":
    unittest.main()
