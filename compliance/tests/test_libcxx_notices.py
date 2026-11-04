"""Refuse partial root texts, credits omissions and inflated C++ attribution."""

import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import verify_libcxx_notices as subject


class LibcxxNoticeTests(unittest.TestCase):
    def setUp(self):
        self.source = TOOLS.parents[1]
        self.report = json.loads((self.source / subject.PACKET / "manifest.json").read_text())
        self.index = json.loads((self.source / subject.linkage.PACKET / "result.json").read_text())["index"]
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        paths = ["compliance/inventory.json", "compliance/generated/THIRD_PARTY_NOTICES.md"]
        paths.extend(row["path"] for row in self.report["license_texts"])
        for name in paths:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.source / name, p)

    def test_complete_actual_texts_image_linkage_inventory_and_corpus_pass(self):
        value = subject.verify(self.source)
        self.assertEqual(value["complete_texts"], 4)
        self.assertEqual(value["mapped_cpp_members"], 18)
        self.assertEqual(value["text_bytes"], 39193)

    def test_license_exception_legacy_text_and_partial_credits_cannot_be_dropped(self):
        for row in self.report["license_texts"]:
            p = self.root / row["path"]
            original = p.read_bytes()
            replacements = [(b"LLVM Exceptions", b"omitted exceptions"), (b"Redistributions", b"omitted conditions")] if p.name.endswith("LICENSE.txt") else [(b"partial list", b"uncredited")]
            for old, new in replacements:
                self.assertIn(old, original)
                p.write_bytes(original.replace(old, new))
                with self.assertRaisesRegex(ValueError, r"Complete C\+\+ root text changed"):
                    subject.validate(self.report, self.root, self.index)
            p.write_bytes(original)

    def test_similar_runtime_licences_are_not_interchangeable(self):
        rows = [r for r in self.report["license_texts"] if r["path"].endswith("LICENSE.txt")]
        a, b = [self.root / r["path"] for r in rows]
        self.assertNotEqual(a.read_bytes(), b.read_bytes())
        a.write_bytes(b.read_bytes())
        with self.assertRaises(ValueError):
            subject.validate(self.report, self.root, self.index)

    def test_attribution_overclaim_missing_or_duplicate_record_rejected(self):
        p = self.root / "compliance/inventory.json"
        original = json.loads(p.read_text())
        ident = self.report["components"][0]["id"]
        for kind in ("claim", "missing", "duplicate"):
            record = copy.deepcopy(original)
            row = next(c for c in record["components"] if c["id"] == ident)
            if kind == "claim":
                row["resolution"] = "exact-final-retention-and-independent-rights-proved"
            elif kind == "missing":
                record["components"].remove(row)
            else:
                record["components"].append(row)
            p.write_text(json.dumps(record))
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, r"Qualified C\+\+ attribution"):
                subject.validate(self.report, self.root, self.index)

    def test_generated_complete_text_omission_rejected(self):
        p = self.root / "compliance/generated/THIRD_PARTY_NOTICES.md"
        text = (self.root / self.report["license_texts"][0]["path"]).read_text()
        original = p.read_text()
        self.assertIn(text, original)
        p.write_text(original.replace(text, "omitted C++ notice"))
        with self.assertRaisesRegex(ValueError, "corpus omits complete"):
            subject.validate(self.report, self.root, self.index)

    def test_image_reference_and_link_member_substitutions_rejected(self):
        for kind in ("image", "source", "members", "scope"):
            report = copy.deepcopy(self.report)
            if kind == "image":
                report["image_child"] = "a" * 64
            elif kind == "source":
                report["files"][0]["source_reference_equal"] = False
            elif kind == "members":
                report["mapped_archive_members"]["libcxx"].pop()
            else:
                report["scope"] = "all per-file rights cleared"
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                subject.validate(report, self.root, self.index)

    def test_actual_capture_changed_text_missing_file_or_wrong_layer_rejected(self):
        texts = {r["image_path"]: (self.root / r["path"]).read_bytes() for r in self.report["license_texts"]}
        actual = {r["path"]: (texts[r["path"]], r["layer"]) for r in self.report["files"]}
        subject.checked_capture(actual, self.report, texts)
        first = next(iter(actual))
        for kind in ("text", "missing", "layer"):
            value = dict(actual)
            if kind == "text":
                value[first] = (b"different", actual[first][1])
            elif kind == "missing":
                del value[first]
            else:
                value[first] = (actual[first][0], "sha256:" + "a" * 64)
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                subject.checked_capture(value, self.report, texts)


if __name__ == "__main__":
    unittest.main()
