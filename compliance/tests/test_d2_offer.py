"""Negative controls for the D2 corresponding-source archive verifier."""

import io
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "compliance" / "tools"))

import verify_d2_offer  # noqa: E402
import prepare_d2_source_offer as prepare  # noqa: E402


class D2OfferVerifierTests(unittest.TestCase):
    def test_current_snapshot_verification_rejects_stale_or_duplicate_archive(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'review.tar.gz'
            name = 'distribution-snapshot/THIRD_PARTY_NOTICES.md'
            current = {name: b'current notice'}
            with tarfile.open(path, 'w:gz') as archive:
                data = b'stale!! notice'
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            with self.assertRaisesRegex(ValueError, 'differs from current selected inputs'):
                prepare.verify_archive(path, current)
            with tarfile.open(path, 'w:gz') as archive:
                for _ in range(2):
                    member = tarfile.TarInfo(name)
                    member.size = len(current[name])
                    archive.addfile(member, io.BytesIO(current[name]))
            with self.assertRaisesRegex(ValueError, 'unsafe or duplicate'):
                prepare.verify_archive(path, current)
            with tarfile.open(path, 'w:gz') as archive:
                member = tarfile.TarInfo('unexpected.bin')
                member.size = 1024 * 1024
                archive.addfile(member, io.BytesIO(b'x' * member.size))
            with self.assertRaisesRegex(ValueError, 'unsafe or duplicate'):
                prepare.verify_archive(path, current)

    def verify_members(self, members, reviewed_manifest=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive_path = root / "offer.tar.gz"
            graph_path = root / "graph.json"
            shipped_path = root / "browser.js"
            manifest_path = root / "manifest.json"
            graph_path.write_text("{}")
            shipped_path.write_bytes(b"")
            manifest_path.write_bytes(reviewed_manifest if reviewed_manifest is not None
                                      else next((payload for name, payload in members
                                                 if name == "manifest.json"), b""))
            with tarfile.open(archive_path, "w:gz") as archive:
                for name, payload in members:
                    info = tarfile.TarInfo(name)
                    info.size = len(payload)
                    archive.addfile(info, io.BytesIO(payload))
            verify_d2_offer.verify(archive_path, graph_path, shipped_path, manifest_path)

    def test_duplicate_member_is_rejected_before_manifest_use(self):
        manifest = json.dumps({"files": []}).encode()
        with self.assertRaisesRegex(ValueError, "duplicate archive member"):
            self.verify_members([("manifest.json", manifest), ("manifest.json", manifest)])

    def test_traversal_member_is_rejected_without_extraction(self):
        with self.assertRaisesRegex(ValueError, "non-file or unsafe archive member"):
            self.verify_members([("../outside", b"untrusted")])

    def test_archive_manifest_must_match_reviewed_manifest(self):
        with self.assertRaisesRegex(ValueError, "archive manifest differs"):
            self.verify_members([("manifest.json", b"{}")], reviewed_manifest=b"changed")

    def test_manifest_hash_mismatch_is_rejected(self):
        manifest = json.dumps({"files": [{"path": "payload", "size": 3, "sha256": "0" * 64}]}).encode()
        with self.assertRaisesRegex(ValueError, "manifest size/hash mismatch"):
            self.verify_members([("manifest.json", manifest), ("payload", b"abc")])

    def test_browser_patch_must_apply_to_the_published_file(self):
        published = b"first\nold export\nlast\n"
        shipped = b"first\nnew export\nlast\n"
        patch = (b"--- a/dist/browser/index.js\n+++ b/dist/browser/index.js\n"
                 b"@@ -1,3 +1,3 @@\n first\n-old export\n+new export\n last\n")
        verify_d2_offer.verify_browser_patch(patch, published, shipped)
        with self.assertRaisesRegex(ValueError, "does not match one published location"):
            verify_d2_offer.verify_browser_patch(patch.replace(b" first\n", b" wrong\n"),
                                                 published, shipped)
        with self.assertRaisesRegex(ValueError, "does not reproduce the shipped file"):
            verify_d2_offer.verify_browser_patch(patch.replace(b"+new export", b"+wrong export"),
                                                 published, shipped)


if __name__ == "__main__":
    unittest.main()
