"""Offline build-input and complete-output refusal controls."""

import json
import base64
import hashlib
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import rebuild_viz_renderer as renderer


class VizRendererRebuildTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.built = Path(self.temp.name) / "built"
        self.built.mkdir()
        self.contents = {name: ("fixture " + name).encode() for name in renderer.GENERATED}
        self.expected = {name: renderer.backend.record(data) for name, data in self.contents.items()}
        for name, data in self.contents.items():
            (self.built / name).write_bytes(data)
        (self.built / "versions.txt").write_text("v24.19.0\n12.0.2\n")

    def test_all_five_outputs_match_without_execution(self):
        result = renderer.compare_files(self.built, self.expected)
        self.assertIs(result["all_outputs_equal"], True)
        self.assertEqual(result["measured_versions"], {"node": "v24.19.0", "npm": "12.0.2"})

    def test_each_generated_difference_retains_all_identities(self):
        for name, original in self.contents.items():
            with self.subTest(file=name):
                p = self.built / name
                p.write_bytes(original + b"different")
                result = renderer.compare_files(self.built, self.expected)
                self.assertIs(result["all_outputs_equal"], False)
                self.assertEqual(set(result["actual_outputs"]), set(renderer.GENERATED))
                self.assertNotEqual(result["actual_outputs"][name], self.expected[name])
                p.write_bytes(original)

    def test_missing_extra_and_linked_generated_files_rejected(self):
        p = self.built / "viz-global.js"
        p.unlink()
        with self.assertRaisesRegex(ValueError, "file set"):
            renderer.compare_files(self.built, self.expected)
        p.symlink_to(self.built / "backend.js")
        with self.assertRaisesRegex(ValueError, "regular file"):
            renderer.compare_files(self.built, self.expected)
        p.unlink()
        p.write_bytes(self.contents[p.name])
        (self.built / "extra.js").write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "file set"):
            renderer.compare_files(self.built, self.expected)

    def test_measured_versions_cannot_be_missing_or_fabricated(self):
        for value in ["v22.16.0\n12.0.2\n", "v24.19.0\n", "v24.19.0\nunknown\n", "v24.19.0\n12.0.2\nextra\n"]:
            (self.built / "versions.txt").write_text(value)
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "Measured"):
                renderer.compare_files(self.built, self.expected)

    def test_node_reference_binds_actual_publisher_and_official_checksum(self):
        info = renderer.node_reference(self.root)
        self.assertEqual(info["version"], "24.19.0")
        self.assertEqual(info["bytes"], 31633904)

    def test_changed_node_reference_checksum_or_publisher_rejected(self):
        root = Path(self.temp.name) / "repo"
        names = [renderer.PACKET + "/node-reference.json", renderer.PACKET + "/SHASUMS256.txt",
                 renderer.PACKET + "/npm-publisher.json", "compliance/evidence/viz-js-3.30.0/downloads.json"]
        for name in names:
            p = root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.root / name, p)
        for name in names[:3]:
            p = root / name
            original = p.read_bytes()
            if name.endswith("node-reference.json"):
                info = json.loads(original)
                info["url"] = "https://example.invalid/node.tar.xz"
                p.write_text(json.dumps(info))
            else:
                p.write_bytes(original + b"changed")
            with self.subTest(file=name), self.assertRaises(ValueError):
                renderer.node_reference(root)
            p.write_bytes(original)

    def test_changed_frozen_lock_refused_before_dependency_resolution(self):
        with self.assertRaisesRegex(ValueError, "Frozen npm lock differs"):
            renderer.check_lock(b'{"lockfileVersion": 3, "packages": {}}', self.root)

    def test_backend_recipe_stays_identical_with_fully_offline_install(self):
        original = (self.root / "compliance/evidence/graphviz-backend-reproduction/upstream-Dockerfile").read_bytes()
        recipe = renderer.recipe(original, self.root)
        self.assertTrue(recipe.startswith(renderer.backend.derive_recipe(original, self.root)))
        self.assertEqual(recipe.count(b"RUN --network=default "), 0)
        self.assertIn(b"npm clean-install --ignore-scripts --offline --cache=/npm-cache --no-audit --no-fund", recipe)
        self.assertIn(b"touch lib/backend.js && make", recipe)

    def test_dependency_integrity_changed_missing_extra_and_linked_objects_rejected(self):
        folder = Path(self.temp.name) / "packages"
        folder.mkdir()
        data = b"fixture compressed package bytes; never executed"
        integrity = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()
        plan = {"object.tgz": {"integrity": integrity, "url": "https://registry.npmjs.org/fixture.tgz"}}
        p = folder / "object.tgz"
        p.write_bytes(data)
        self.assertEqual(renderer.checked_packages(plan, folder)["total_bytes"], len(data))
        p.write_bytes(data + b"changed")
        with self.assertRaisesRegex(ValueError, "integrity differs"):
            renderer.checked_packages(plan, folder)
        p.unlink()
        with self.assertRaisesRegex(ValueError, "membership"):
            renderer.checked_packages(plan, folder)
        p.symlink_to(self.built / "backend.js")
        with self.assertRaisesRegex(ValueError, "regular file"):
            renderer.checked_packages(plan, folder)
        p.unlink()
        p.write_bytes(data)
        (folder / "extra.tgz").write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "membership"):
            renderer.checked_packages(plan, folder)


if __name__ == "__main__":
    unittest.main()
