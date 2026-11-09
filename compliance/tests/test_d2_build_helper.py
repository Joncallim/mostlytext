"""Static negative controls for the retained D2 build-helper source capture."""

import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import verify_d2_build_helper as helper


class D2BuildHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        evidence = helper.ROOT / helper.EVIDENCE
        cls.archive = (evidence / helper.ARCHIVE).read_bytes()
        cls.expected = json.loads((evidence / "verified-source-submodule.json").read_text())["files_sha256"]

    def repack(self, change):
        output = io.BytesIO()
        with tarfile.open(fileobj=io.BytesIO(self.archive), mode="r:gz") as source:
            members = [(member, source.extractfile(member).read()) for member in source]
        with tarfile.open(fileobj=output, mode="w:gz") as target:
            for index, (member, body) in enumerate(members):
                member, body = change(index, member, body)
                target.addfile(member, io.BytesIO(body) if member.isfile() else None)
        return output.getvalue()

    def test_exact_retained_source_packet(self):
        result = helper.verify()
        self.assertEqual(result["files"], 37)
        self.assertEqual(result["archive_sha256"], helper.ARCHIVE_SHA256)
        self.assertIn("LICENSE", self.expected)

    def test_changed_archive_refused_before_member_review(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary) / helper.EVIDENCE
            evidence.mkdir(parents=True)
            original = helper.ROOT / helper.EVIDENCE
            for name in (helper.ARCHIVE, "verified-source-submodule.json", "manifest.json"):
                (evidence / name).write_bytes((original / name).read_bytes())
            with (evidence / helper.ARCHIVE).open("ab") as stream:
                stream.write(b"changed")
            with self.assertRaisesRegex(ValueError, "reviewed bytes"):
                helper.verify(Path(temporary))

    def test_member_mutation_refused(self):
        def change_license(index, member, body):
            if index == 3:
                body += b"changed"
                member.size = len(body)
            return member, body
        altered = self.repack(change_license)
        with self.assertRaisesRegex(ValueError, "member differs"):
            helper.verify_members(altered, self.expected)

    def test_extra_and_unsafe_member_refused(self):
        for name in ("terrastruct-ci-2594100a/../escape",
                     "terrastruct-ci-2594100a/unexpected.txt"):
            with self.subTest(name=name):
                altered = self.repack(lambda i, member, body:
                                      (self.renamed(member, name), body) if i == 0 else (member, body))
                with self.assertRaisesRegex(ValueError, "unsafe, duplicate or extra"):
                    helper.verify_members(altered, self.expected)

    def test_link_refused(self):
        def link_first(index, member, body):
            if index == 0:
                member.type = tarfile.SYMTYPE
                member.linkname = "LICENSE"
                member.size = 0
                return member, b""
            return member, body
        with self.assertRaisesRegex(ValueError, "member type or path"):
            helper.verify_members(self.repack(link_first), self.expected)

    @staticmethod
    def renamed(member, name):
        member.name = name
        return member


if __name__ == "__main__":
    unittest.main()
