#!/usr/bin/env python3
"""Pure source-overlay controls; never executes an application."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("prepare-native-startup-observation.py")
spec = importlib.util.spec_from_file_location("startup_observation", SCRIPT)
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)
SOURCE = SCRIPT.resolve().parents[2]


class ObservationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repository"
        self.repo.mkdir()
        for name in observer.FILES.values():
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / name, target)
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True, capture_output=True)
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                        "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "-qm", "Preserve original startup inputs"], cwd=self.repo, check=True)
        self.output = self.root / "overlay.json"

    def test_complete_recipe_reconstructs_exactly_three_sources(self):
        result = observer.prepare(self.repo, self.output)
        self.assertTrue(result["complete"])
        self.assertEqual(set(result["files"]), set(observer.FILES.values()))
        observer.verify(self.repo, json.loads(self.output.read_text()))
        legacy = (self.repo / observer.FILES["legacy"]).read_text()
        self.assertIn('"resume=\\(result)"', legacy)
        self.assertIn("MOSTLYTEXT_NATIVE_STARTUP_TRACE", legacy)

    def test_changed_last_input_cannot_partially_modify_earlier_inputs(self):
        target = self.repo / observer.FILES["delegate"]
        target.write_text(target.read_text() + "\n// Unreviewed input\n")
        before = {p: (self.repo / p).read_bytes() for p in observer.FILES.values()}
        with self.assertRaises(AssertionError):
            observer.prepare(self.repo, self.output)
        self.assertEqual(before, {p: (self.repo / p).read_bytes() for p in before})
        self.assertFalse(self.output.exists())

    def test_modified_executed_source_cannot_keep_a_verified_receipt(self):
        result = observer.prepare(self.repo, self.output)
        target = self.repo / observer.FILES["legacy"]
        target.write_text(target.read_text() + "\n// Different executed source\n")
        with self.assertRaises(AssertionError):
            observer.verify(self.repo, result)

    def test_existing_record_is_preserved_without_source_changes(self):
        self.output.write_bytes(b"preserve previous first outcome")
        before = {p: (self.repo / p).read_bytes() for p in observer.FILES.values()}
        with self.assertRaises(AssertionError):
            observer.prepare(self.repo, self.output)
        self.assertEqual(self.output.read_bytes(), b"preserve previous first outcome")
        self.assertEqual(before, {p: (self.repo / p).read_bytes() for p in before})

    def test_self_consistent_unreviewed_recipe_is_refused(self):
        result = observer.prepare(self.repo, self.output)
        name = observer.FILES["legacy"]
        item = result["files"][name]
        item["replacements"][0]["replacement"] += "\n// Unreviewed operation\n"
        text = subprocess.check_output(["git", "show", "HEAD:" + name], cwd=self.repo, text=True)
        for step in item["replacements"]:
            text = text.replace(step["original"], step["replacement"], 1 if step["first_only"] else step["expected_count"])
        (self.repo / name).write_text(text)
        item["executed_sha256"] = observer.sha(text.encode())
        with self.assertRaises(AssertionError):
            observer.verify(self.repo, result)


if __name__ == "__main__":
    unittest.main()
