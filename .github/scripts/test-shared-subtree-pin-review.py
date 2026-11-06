#!/usr/bin/env python3
"""Pure refusal controls for the C probe's exact dependency authority."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("comparison_probe", Path(__file__).with_name(
    "run-shared-subtree-comparison-probe.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RuntimePinAuthorityTests(unittest.TestCase):
    def setUp(self):
        repo = Path(__file__).resolve().parents[2]
        self.lock = json.loads((repo / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())

    def test_actual_complete_graph_preserves_the_two_reviewed_source_owners(self):
        pins = module.checked_pins(self.lock)
        self.assertEqual(len(pins), 24)
        for name, owner in module.OWNERS.items():
            self.assertEqual(pins[name]["location"], owner)

    def test_other_owners_and_nonimmutable_revisions_are_refused_before_fetch(self):
        for name in module.OWNERS:
            for key, value in [("location", "https://github.com/other/unreviewed"), ("revision", "main")]:
                changed = copy.deepcopy(self.lock)
                row = next(row for row in changed["pins"] if row["identity"] == name)
                if key == "location":
                    row[key] = value
                else:
                    row["state"][key] = value
                with self.subTest(name=name, key=key), self.assertRaises(SystemExit):
                    module.checked_pins(changed)

    def test_unchanged_original_cannot_be_qualified_as_a_candidate(self):
        row = next(row for row in self.lock["pins"] if row["identity"] == "tree-sitter")
        row["state"]["revision"] = module.BASE
        with self.assertRaises(SystemExit):
            module.checked_pins(self.lock)

    def test_duplicate_missing_and_extra_graph_entries_are_refused(self):
        duplicate = copy.deepcopy(self.lock)
        duplicate["pins"].append(copy.deepcopy(duplicate["pins"][0]))
        missing = copy.deepcopy(self.lock)
        missing["pins"] = [row for row in missing["pins"] if row["identity"] != "tree-sitter-json"]
        extra = copy.deepcopy(self.lock)
        added = copy.deepcopy(extra["pins"][0])
        added["identity"] = "unreviewed-extra"
        extra["pins"].append(added)
        for changed in [duplicate, missing, extra]:
            with self.subTest(changed=changed), self.assertRaises(SystemExit):
                module.checked_pins(changed)


if __name__ == "__main__":
    unittest.main()
