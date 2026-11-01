"""The executable report must cover the independently source-backed declaration map."""

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "legacy_map", ROOT / "planning/downstream/tools/check_legacy_preference_map.py"
)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class LegacyReportCoverageTests(unittest.TestCase):
    def setUp(self):
        self.record = json.loads((ROOT / "planning/downstream/legacy-preference-dispositions.json").read_text())

    def test_report_matches_exhaustive_map(self):
        CHECKER.validate_report(self.record, ROOT)

    def test_removed_declaration_is_rejected(self):
        altered = copy.deepcopy(self.record)
        altered["entries"].pop()
        with self.assertRaisesRegex(ValueError, "coverage mismatch"):
            CHECKER.validate_report(altered, ROOT)

    def test_policy_drift_is_rejected(self):
        altered = copy.deepcopy(self.record)
        altered["entries"][0]["report_policy"] = "mapped"
        with self.assertRaisesRegex(ValueError, "policy mismatch"):
            CHECKER.validate_report(altered, ROOT)

    def test_duplicate_map_declaration_is_rejected(self):
        altered = copy.deepcopy(self.record)
        altered["entries"].append(copy.deepcopy(altered["entries"][0]))
        with self.assertRaisesRegex(ValueError, "coverage mismatch"):
            CHECKER.validate_report(altered, ROOT)

    def test_duplicate_catalog_member_is_rejected(self):
        relative = Path("MacDown2/Packages/MacDownKit/Sources/AppSettings/LegacyPreferenceCatalog.swift")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / relative
            target.parent.mkdir(parents=True)
            target.write_text((ROOT / relative).read_text() + '\n.init("editorSmartHome", .boolean, .mapped)\n')
            with self.assertRaisesRegex(ValueError, "coverage mismatch"):
                CHECKER.validate_report(self.record, root)
