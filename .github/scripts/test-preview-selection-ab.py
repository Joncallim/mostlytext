#!/usr/bin/env python3
"""Pure controls for the hosted same-source Textual selection A/B."""

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest


SCRIPT = Path(__file__).with_name("preview-selection-ab.py")
spec = importlib.util.spec_from_file_location("preview_selection_ab", SCRIPT)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class PreviewSelectionABTests(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads(subprocess.check_output([
            "git", "show", "HEAD:" + str(probe.LOCK)
        ]))

    def test_base_pin_and_only_the_selected_revision_are_admitted(self):
        probe.validate_pins(self.lock, self.lock, probe.NEW)
        changed = copy.deepcopy(self.lock)
        textual = next(pin for pin in changed["pins"] if pin["identity"] == "textual")
        textual["state"] = {"revision": probe.OLD}
        probe.validate_pins(self.lock, changed, probe.OLD)
        with self.assertRaises(ValueError):
            probe.validate_pins(self.lock, changed, probe.NEW)

    def test_an_unrelated_dependency_or_added_pin_fails(self):
        changed = copy.deepcopy(self.lock)
        other = next(pin for pin in changed["pins"] if pin["identity"] != "textual")
        other["state"]["revision"] = "0" * 40
        with self.assertRaises(ValueError):
            probe.validate_pins(self.lock, changed, probe.NEW)
        changed = copy.deepcopy(self.lock)
        changed["pins"].append(changed["pins"][0])
        with self.assertRaises(ValueError):
            probe.validate_pins(self.lock, changed, probe.NEW)

    def test_the_same_app_test_source_allows_only_four_pin_metadata_files(self):
        before = {"MacDown2/MacDown2Tests/SecuredMarkdownMountedTests.swift": "test",
                  **{path: "original" for path in probe.CHANGED_PIN_PATHS}}
        old = {**before, **{path: "old" for path in probe.CHANGED_PIN_PATHS}}
        self.assertEqual(probe.source_delta(before, old, "old"), sorted(probe.CHANGED_PIN_PATHS))
        self.assertEqual(probe.source_delta(before, before, "new"), [])
        old["MacDown2/MacDown2Tests/SecuredMarkdownMountedTests.swift"] = "changed test"
        with self.assertRaises(ValueError):
            probe.source_delta(before, old, "old")

    def test_exact_revision_replacement_refuses_ambiguous_inputs(self):
        self.assertEqual(probe.replace_exact("before NEW after", "NEW", "OLD"), "before OLD after")
        for source in ["before after", "NEW and NEW"]:
            with self.assertRaises(ValueError):
                probe.replace_exact(source, "NEW", "OLD")

    def test_fixed_mounted_copy_test_and_repetition_count(self):
        self.assertEqual(probe.REPEATS, 10)
        self.assertEqual(probe.TEST, "-only-testing:MacDown2Tests/SecuredMarkdownMountedTests")
        self.assertIn(probe.TEST_URL, probe.EXPECTED_TEST_URLS)
        self.assertEqual(len(probe.EXPECTED_TEST_URLS), 4)
        nodes = [{"nodeIdentifierURL": identifier, "result": "Passed"}
                 for identifier in probe.EXPECTED_TEST_URLS]
        selected = probe.selected_test_results({"testNodes": nodes + [{"nodeIdentifierURL": "test://other"}]})
        self.assertEqual(set(selected), {(identifier, "Passed") for identifier in probe.EXPECTED_TEST_URLS})
        self.assertEqual(len(selected), 4)


if __name__ == "__main__":
    unittest.main()
