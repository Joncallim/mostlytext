#!/usr/bin/env python3
"""Source-only controls for the mounted Textual selection correlation receipt."""

import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest


SCRIPT = Path(__file__).with_name("verify-preview-inline-selection-correlation.py")
ROOT = SCRIPT.parents[2]
TEXTUAL_REVISION = "e75d3a188d2a056757de015dbd3344bffea23fd4"
spec = importlib.util.spec_from_file_location("preview_inline_selection_correlation", SCRIPT)
correlation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(correlation)


def sample_log() -> str:
    lines = [correlation.ORACLE]
    for generation in range(3, 13):
        load_id = f"00000000-0000-0000-0000-{generation:012X}"
        view_id = "0x100"
        model_id = f"0x{generation:03x}"
        lines.extend([
            f"TEXTUAL_SELECTION_LAYOUT loadID={load_id} modelID=ObjectIdentifier({model_id}) "
            "phase=offered offered=layouts=1 attachmentRuns=1",
            f"TEXTUAL_SELECTION_LAYOUT loadID={load_id} modelID=ObjectIdentifier({model_id}) "
            "phase=task-after stored=layouts=1 attachmentRuns=1",
            f"TEXTUAL_NATIVE_SELECTION loadID={load_id} viewID=ObjectIdentifier({view_id}) "
            f"modelID=ObjectIdentifier({model_id}) phase=update stored=layouts=1 attachmentRuns=1",
            f"MOUNTED_INLINE_INSTANCE phase=repeat-copy-complete-{generation} expectedLoadID={load_id} "
            f"selectedViewID=Optional(ObjectIdentifier({view_id})) "
            f"selectedModelID=Optional(ObjectIdentifier({model_id})) "
            "selectedModelLayout=layouts=1 attachmentRuns=1 selectedViewLoadID=unobserved",
        ])
    lines.append("✔ Test run with 56 tests in 17 suites passed after 31 seconds.")
    return "\n".join(lines)


class CorrelationTests(unittest.TestCase):
    def test_verifier_and_controls_are_in_compiled_source_inventory(self):
        inventory = (ROOT / ".github/scripts/verify-preview-grant-probe.py").read_text()
        self.assertIn('".github/scripts/verify-preview-inline-selection-correlation.py"', inventory)
        self.assertIn('".github/scripts/test-preview-inline-selection-correlation.py"', inventory)

    def test_app_and_package_graph_pin_the_exact_candidate(self):
        manifest = (ROOT / "MacDown2/Packages/MacDownKit/Package.swift").read_text()
        project = (ROOT / "MacDown2/project.yml").read_text()
        lock = json.loads((ROOT / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())
        textual = next(pin for pin in lock["pins"] if pin["identity"] == "textual")
        self.assertEqual(textual["state"]["revision"], TEXTUAL_REVISION)
        self.assertRegex(manifest, re.escape('url: "https://github.com/Joncallim/textual", revision: "'
                                             + TEXTUAL_REVISION + '"'))
        self.assertIn("revision: " + TEXTUAL_REVISION, project)

    def test_all_ten_generations_bind_the_rendered_layout_to_native_model(self):
        generations, errors = correlation.inspect(sample_log())
        self.assertEqual(errors, [])
        self.assertEqual([item["generation"] for item in generations], list(range(3, 13)))
        self.assertTrue(all(item["offered_attachment_layout"] and item["stored_attachment_layout"]
                            and item["selected_native_model_updated"]
                            and item["selected_layout_attachment_runs"] > 0
                            and item["offered_line"] < item["task_after_line"] < item["completion_line"]
                            and item["native_update_line"] < item["completion_line"]
                            for item in generations))

    def test_missing_rendered_attachment_fails_the_same_generation(self):
        log = sample_log().replace(
            "phase=offered offered=layouts=1 attachmentRuns=1",
            "phase=offered offered=layouts=1 attachmentRuns=0", 1,
        )
        _, errors = correlation.inspect(log)
        self.assertIn("generation 3: selected model was not offered an attachment layout before Copy", errors)

    def test_native_model_mismatch_fails_even_when_layout_was_published(self):
        log = sample_log().replace(
            "selectedModelID=Optional(ObjectIdentifier(0x003))",
            "selectedModelID=Optional(ObjectIdentifier(0x999))", 1,
        )
        _, errors = correlation.inspect(log)
        self.assertIn("generation 3: selected model did not retain an attachment layout after offer and before Copy", errors)
        self.assertIn("generation 3: selected native view/model lacked a positive update before Copy", errors)

    def test_missing_native_update_and_failed_suite_are_rejected(self):
        log = sample_log().replace(
            "phase=update stored=layouts=1 attachmentRuns=1",
            "phase=missing stored=layouts=1 attachmentRuns=1", 1,
        ).replace("suites passed", "suites failed")
        _, errors = correlation.inspect(log)
        self.assertIn("generation 3: selected native view/model lacked a positive update before Copy", errors)
        self.assertIn("mounted app test pass summary missing", errors)

    def test_plain_native_update_is_rejected(self):
        log = sample_log().replace(
            "phase=update stored=layouts=1 attachmentRuns=1",
            "phase=update stored=layouts=1 attachmentRuns=0", 1,
        )
        _, errors = correlation.inspect(log)
        self.assertIn("generation 3: selected native view/model lacked a positive update before Copy", errors)

    def test_late_native_update_is_rejected(self):
        lines = sample_log().splitlines()
        update = lines.pop(next(index for index, line in enumerate(lines)
                                if "phase=update stored=" in line))
        completion = next(index for index, line in enumerate(lines)
                          if "phase=repeat-copy-complete-3 " in line)
        lines.insert(completion + 1, update)
        _, errors = correlation.inspect("\n".join(lines))
        self.assertIn("generation 3: selected native view/model lacked a positive update before Copy", errors)

    def test_late_offer_is_rejected(self):
        lines = sample_log().splitlines()
        offer = lines.pop(next(index for index, line in enumerate(lines) if "phase=offered " in line))
        completion = next(index for index, line in enumerate(lines)
                          if "phase=repeat-copy-complete-3 " in line)
        lines.insert(completion + 1, offer)
        _, errors = correlation.inspect("\n".join(lines))
        self.assertIn("generation 3: selected model was not offered an attachment layout before Copy", errors)
        self.assertIn("generation 3: selected model did not retain an attachment layout after offer and before Copy", errors)

    def test_task_before_offer_is_rejected(self):
        lines = sample_log().splitlines()
        lines[1], lines[2] = lines[2], lines[1]
        _, errors = correlation.inspect("\n".join(lines))
        self.assertIn("generation 3: selected model did not retain an attachment layout after offer and before Copy", errors)

    def test_task_after_copy_is_rejected(self):
        lines = sample_log().splitlines()
        task = lines.pop(next(index for index, line in enumerate(lines) if "phase=task-after " in line))
        completion = next(index for index, line in enumerate(lines)
                          if "phase=repeat-copy-complete-3 " in line)
        lines.insert(completion + 1, task)
        _, errors = correlation.inspect("\n".join(lines))
        self.assertIn("generation 3: selected model did not retain an attachment layout after offer and before Copy", errors)

    def test_selected_model_must_hold_attachment_at_completion(self):
        log = sample_log().replace(
            "selectedModelLayout=layouts=1 attachmentRuns=1",
            "selectedModelLayout=layouts=1 attachmentRuns=0", 1,
        )
        _, errors = correlation.inspect(log)
        self.assertIn("generation 3: selected native model held no attachment at Copy completion", errors)


if __name__ == "__main__":
    unittest.main()
