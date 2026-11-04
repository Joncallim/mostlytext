"""Captured complete renderer receipt binding and refusal controls."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import shutil

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import rebuild_viz_renderer as renderer
import verify_viz_renderer as proof


class CapturedVizRendererTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.result = json.loads((self.root / renderer.PACKET / "result.json").read_text())

    def test_complete_receipt_matches_all_five_outputs_and_actual_shipped_resource(self):
        result = proof.verify(self.root)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["generated_files"], 5)

    def test_each_changed_output_and_false_equality_claim_rejected(self):
        for name in renderer.GENERATED:
            value = copy.deepcopy(self.result)
            value["actual_outputs"][name]["sha256"] = "a" * 64
            with self.subTest(file=name), self.assertRaisesRegex(ValueError, "Complete generated"):
                proof.validate(value, self.root)
        for claim in (False, 1):
            value = copy.deepcopy(self.result)
            value["all_outputs_equal"] = claim
            with self.subTest(claim=claim), self.assertRaisesRegex(ValueError, "Complete generated"):
                proof.validate(value, self.root)

    def test_coherent_input_source_recipe_lock_or_tool_substitution_rejected(self):
        for kind in ("node", "recipe", "lock", "source", "tool", "expected", "dependency"):
            value = copy.deepcopy(self.result)
            inputs = value["inputs"]
            if kind == "node":
                inputs["node"]["sha256"] = "a" * 64
            elif kind == "recipe":
                inputs["context"]["Dockerfile"]["sha256"] = "a" * 64
            elif kind == "lock":
                inputs["lock"]["resolved_registry_inputs"] -= 1
            elif kind == "source":
                inputs["context"]["viz-source-99da545.tar.gz"]["sha256"] = "a" * 64
            elif kind == "tool":
                inputs["tool_sha256"] = "a" * 64
            elif kind == "dependency":
                name = next(iter(inputs["dependencies"]["objects"]))
                inputs["dependencies"]["objects"][name]["sha256"] = "a" * 64
            else:
                inputs["expected_outputs"]["metadata.js"]["bytes"] += 1
                value["actual_outputs"]["metadata.js"]["bytes"] += 1
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "binding differs"):
                proof.validate(value, self.root)

    def test_false_scope_identity_versions_and_extra_rights_claim_rejected(self):
        for kind in ("scope", "head", "url", "versions", "extra"):
            value = copy.deepcopy(self.result)
            if kind == "scope":
                value["scope"] = "complete independent clearance"
            elif kind == "head":
                value["hosted"]["source_head"] = "wrong"
            elif kind == "url":
                value["hosted"]["url"] = "https://example.invalid/receipt"
            elif kind == "versions":
                value["measured_versions"]["node"] = "v22.16.0"
            else:
                value["source_offer_verified"] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                proof.validate(value, self.root)

    def test_raw_receipt_pin_rejects_even_whitespace_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / renderer.PACKET
            folder.mkdir(parents=True)
            (folder / "result.json").write_bytes((self.root / renderer.PACKET / "result.json").read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "receipt differs"):
                proof.verify(root)

    def test_dependency_receipt_refuses_coherent_missing_wrong_lock_and_oversized_objects(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            names = [renderer.PACKET + "/package-lock.json", renderer.PACKET + "/dependencies.json",
                     "compliance/evidence/viz-js-3.30.0/source-audit.json"]
            for name in names:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self.root / name, p)
            p = root / names[1]
            before = p.read_bytes()
            for kind in ("missing", "url", "size", "total"):
                value = json.loads(before)
                first = next(iter(value["objects"]))
                if kind == "missing":
                    del value["objects"][first]
                    value["object_count"] -= 1
                elif kind == "url":
                    value["objects"][first]["url"] = "https://registry.npmjs.org/wrong.tgz"
                elif kind == "size":
                    value["objects"][first]["bytes"] = renderer.MAX_PACKAGE + 1
                else:
                    value["total_bytes"] += 1
                p.write_text(json.dumps(value))
                # Exercise lock/membership/bound rules below the immutable raw
                # receipt pin. Production never replaces this pin dynamically.
                with self.subTest(kind=kind), patch.object(proof, "DEPENDENCIES_SHA256", renderer.backend.sha(p.read_bytes())):
                    with self.assertRaises(ValueError):
                        proof.dependency_receipt(root)


if __name__ == "__main__":
    unittest.main()
