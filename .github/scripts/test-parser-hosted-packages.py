"""Refusal controls for the manual, read-only parser package qualification."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


HERE = Path(__file__).resolve().parent
MODULE = importlib.util.spec_from_file_location("parser_packages", HERE / "qualify-parser-hosted-packages.py")
qualification = importlib.util.module_from_spec(MODULE)
MODULE.loader.exec_module(qualification)


class ParserPackageTests(unittest.TestCase):
    def test_submodule_status_preserves_and_checks_the_leading_marker(self):
        revision = qualification.SUBMODULES["swifttreesitter"]["tree-sitter-swift"]
        expected = {"tree-sitter-swift": revision}
        good = " " + revision + " tree-sitter-swift (eda05af)"
        self.assertEqual(qualification.verify_submodule_status([good], expected), expected)
        for marker in ("-", "+", "U"):
            with self.subTest(marker=marker):
                with self.assertRaisesRegex(ValueError, "uninitialized or differs"):
                    qualification.verify_submodule_status([marker + good[1:]], expected)
        with self.assertRaisesRegex(ValueError, "gitlink differs"):
            qualification.verify_submodule_status([" " + "0" * 40 + " tree-sitter-swift"], expected)
        with self.assertRaisesRegex(ValueError, "gitlink differs"):
            qualification.verify_submodule_status([" " + revision + " other-submodule"], expected)

    def test_ci_job_is_manual_on_the_isolated_ref_and_read_only(self):
        workflow = (HERE.parent / "workflows/ci.yml").read_text()
        job = workflow.split("\n  parser-package-qualification:\n", 1)[1]
        self.assertIn("if: github.event_name == 'workflow_dispatch' && github.repository == 'Joncallim/mostlytext' && github.ref == 'refs/heads/epic/05-parser-hosted-graph'", job)
        self.assertIn("permissions:\n      contents: read\n      actions: read", job)
        self.assertIn("run-id: 42487278217", job)
        self.assertIn("persist-credentials: false", job)
        self.assertEqual(workflow.count("if: github.event_name != 'workflow_dispatch' || github.ref != 'refs/heads/epic/05-parser-hosted-graph'"), 2)

    def test_lock_rejects_wrong_owner_and_revision(self):
        expected = {
            "tree-sitter": {"identity": "tree-sitter", "kind": "remoteSourceControl",
                            "location": "https://github.com/Joncallim/tree-sitter",
                            "state": {"revision": qualification.parser_c.SOURCE["tree-sitter"]["revision"]}}
        }
        with tempfile.TemporaryDirectory() as folder:
            lock = Path(folder) / "Package.resolved"
            lock.write_text(json.dumps({"version": 3, "originHash": "manifest", "pins": list(expected.values())}))
            self.assertEqual(set(qualification.validate_lock(lock, expected)["pins"]), {"tree-sitter"})
            changed = json.loads(lock.read_text())
            changed["pins"][0]["state"]["revision"] = "0" * 40
            lock.write_text(json.dumps(changed))
            with self.assertRaisesRegex(ValueError, "reviewed pin: tree-sitter"):
                qualification.validate_lock(lock, expected)
            changed["pins"][0] = expected["tree-sitter"]
            changed["pins"].append(expected["tree-sitter"])
            lock.write_text(json.dumps(changed))
            with self.assertRaisesRegex(ValueError, "dependency set"):
                qualification.validate_lock(lock, expected)

    def test_manual_owner_event_is_required(self):
        with tempfile.TemporaryDirectory() as folder:
            with mock.patch.dict(qualification.os.environ, {"GITHUB_ACTIONS": "true",
                    "GITHUB_EVENT_NAME": "push", "GITHUB_REPOSITORY": qualification.REPOSITORY,
                    "GITHUB_REF": qualification.REF}, clear=True):
                with self.assertRaisesRegex(ValueError, "manual dispatch"):
                    qualification.require_host(Path(folder))

    def test_first_failure_is_recorded_with_line(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "test.log"
            log.write_text("Test run with 8 tests passed\n0 failures\nerror: failed to compile\n")
            self.assertEqual(qualification.first_failure(log),
                             {"line": 3, "text": "error: failed to compile"})

    def test_fork_manifest_requires_one_exact_change(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source"
            source.mkdir()
            self.git(["init", "-q", str(source)])
            self.git(["config", "user.email", "fixture@example.invalid"], cwd=source)
            self.git(["config", "user.name", "Fixture"], cwd=source)
            old, new = "a" * 40, "b" * 40
            (source / "Package.swift").write_text("revision: \"" + old + "\"\n")
            self.git(["add", "Package.swift"], cwd=source)
            self.git(["commit", "-qm", "old"], cwd=source)
            parent = self.git(["rev-parse", "HEAD"], cwd=source)
            (source / "Package.swift").write_text("revision: \"" + new + "\"\n")
            self.git(["commit", "-qam", "new"], cwd=source)
            revision = self.git(["rev-parse", "HEAD"], cwd=source)
            bare = root / "bare"
            self.git(["clone", "--bare", "-q", str(source), str(bare)])
            facts = {"url": str(source), "revision": revision,
                     "tree": self.git(["rev-parse", "HEAD^{tree}"], cwd=source),
                     "blobs": {"Package.swift": self.git(["rev-parse", "HEAD:Package.swift"], cwd=source)}}
            with mock.patch.dict(qualification.parser_c.SOURCE, {"swifttreesitter": facts}), \
                 mock.patch.dict(qualification.PARENTS, {"swifttreesitter": parent}), \
                 mock.patch.dict(qualification.MANIFEST_REVISIONS, {"swifttreesitter": (old, new)}):
                self.assertEqual(qualification.verify_manifest_change(bare, "swifttreesitter")["changed_files"],
                                 ["Package.swift"])
                with mock.patch.dict(qualification.MANIFEST_REVISIONS,
                                     {"swifttreesitter": (old, "c" * 40)}):
                    with self.assertRaisesRegex(ValueError, "one-pin"):
                        qualification.verify_manifest_change(bare, "swifttreesitter")

    @staticmethod
    def git(arguments, *, cwd=None):
        return subprocess.check_output(["git", *arguments], cwd=cwd, text=True).strip()


if __name__ == "__main__":
    unittest.main()
