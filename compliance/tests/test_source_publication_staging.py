"""Source-only refusal controls for private versioned compliance staging."""

import copy
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import stage_source_publication as staging


def inventory():
    return {
        "product": {"name": "MostlyText", "version": "1.0.0"},
        "components": [
            {"id": "d2", "source_offer": {
                "status": "planned", "location": "https://mostlytext.app/opensource/1.0.0/d2/"}},
            {"id": "viz-js", "source_offer": {
                "status": "planned", "location": "https://mostlytext.app/opensource/1.0.0/graphviz/"}},
        ],
    }


class SourcePublicationStagingTests(unittest.TestCase):
    def test_only_exact_unpublished_source_offer_identity_is_accepted(self):
        expected = inventory()
        self.assertEqual(staging.release_identity(expected), "1.0.0")
        for change in (
            lambda row: row["components"][0]["source_offer"].update(status="verified"),
            lambda row: row["components"][0]["source_offer"].update(materials=[{"url": "public"}]),
            lambda row: row["components"][1]["source_offer"].update(location="https://example.com/"),
            lambda row: row["product"].update(version="../private"),
        ):
            with self.subTest(change=change):
                changed = copy.deepcopy(expected)
                change(changed)
                with self.assertRaises(ValueError):
                    staging.release_identity(changed)

    def test_materials_are_fixed_review_objects_with_internal_checksums(self):
        files = staging.material_files("1.0.0", b"notices", b"sbom", b"d2", b"graphviz", b"patch")
        self.assertEqual(len(files), 8)
        checksums = files["1.0.0/SHA256SUMS"].decode().splitlines()
        self.assertEqual(len(checksums), 7)
        self.assertTrue(any(line.endswith("  d2/d2-browser.patch") for line in checksums))
        self.assertIn(b"not been approved as complete corresponding source",
                      files["1.0.0/d2/index.html"])
        self.assertNotIn(b"/Users/", b"".join(files.values()))
        self.assertNotIn(b"/Volumes/", b"".join(files.values()))

    def test_stage_rejects_overwrite_tampering_extra_paths_and_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / "private-review"
            files = {"REVIEW_ONLY.json": b"review only", "1.0.0/SHA256SUMS": b"hashes",
                     "1.0.0/d2/index.html": b"D2 review"}
            staging.stage(output, files)
            staging.stage(output, files, verify_only=True)
            with self.assertRaisesRegex(ValueError, "overwrite"):
                staging.stage(output, files)
            target = output / "1.0.0/d2/index.html"
            target.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "contents differ"):
                staging.stage(output, files, verify_only=True)
            target.write_bytes(files["1.0.0/d2/index.html"])
            (output / "1.0.0/unexpected").mkdir()
            with self.assertRaisesRegex(ValueError, "directory set differs"):
                staging.stage(output, files, verify_only=True)
            (output / "1.0.0/unexpected").rmdir()
            (output / "1.0.0/extra.txt").write_text("private")
            with self.assertRaisesRegex(ValueError, "file set differs"):
                staging.stage(output, files, verify_only=True)
            (output / "1.0.0/extra.txt").unlink()
            (output / "1.0.0/linked").symlink_to(parent)
            with self.assertRaisesRegex(ValueError, "symlink"):
                staging.stage(output, files, verify_only=True)

    def test_required_input_cannot_be_a_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            source = parent / "source"
            source.write_bytes(b"reviewed")
            link = parent / "link"
            link.symlink_to(source)
            with self.assertRaisesRegex(ValueError, "regular file"):
                staging.require_regular_file(link)

    def test_output_must_be_outside_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            with self.assertRaisesRegex(ValueError, "outside the repository"):
                staging.require_private_output(root, root / "private-review")
            staging.require_private_output(root, Path(temporary) / "private-review")


if __name__ == "__main__":
    unittest.main()
