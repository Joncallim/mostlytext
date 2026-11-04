"""Offline controls for bounded, stage-qualified linker evidence."""

from pathlib import Path
import copy
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import capture_graphviz_link as link
import verify_graphviz_link as proof

MAP = b'''    Addr      Off     Size Out     In      Symbol
       -        8        e TYPE
       -       20       40 CODE
       -       21       10         /prefix/lib/libfixture.a(first.o):(first)
       -       21       10                 first
       -       31       10         /sdk/lib/libc.a(second.o):(second)
'''
WHY = b'''reference\textracted\tsymbol
/tmp/viz.o\t/prefix/lib/libfixture.a(first.o)\tfirst
/prefix/lib/libfixture.a(first.o)\t/sdk/lib/libc.a(second.o)\tsecond
'''


class GraphvizLinkTests(unittest.TestCase):
    def test_complete_index_preserves_reasons_and_link_stage(self):
        value = link.summarize(MAP, WHY)
        self.assertEqual(value["map_rows"], 5)
        self.assertEqual(len(value["extraction_rows"]), 2)
        self.assertEqual(value["extraction_rows"][0]["reference"], "/tmp/viz.o")
        self.assertEqual(value["map_archive_members"], value["extracted_archive_members"])
        self.assertEqual(value["unparsed_extracted_inputs"], [])
        self.assertIn("before subsequent", value["stage"])

    def test_unexpected_extracted_inputs_are_retained(self):
        value = link.summarize(MAP, WHY + b"<internal>\tstandalone.o\t\n")
        self.assertEqual(value["unparsed_extracted_inputs"], [{"line": 4, "extracted": "standalone.o"}])
        self.assertEqual(len(value["extraction_rows"]), 3)

    def test_extraction_is_not_misrepresented_as_complete_map_retention(self):
        value = link.summarize(MAP, WHY.splitlines(True)[0] + WHY.splitlines(True)[1] +
                               b"first\t/sdk/lib/libc.a(extracted-only.o)\tunused\n")
        self.assertEqual(value["mapped_without_extraction_record"], ["/sdk/lib/libc.a(second.o)"])
        self.assertEqual(value["extracted_without_map_record"], ["/sdk/lib/libc.a(extracted-only.o)"])

    def test_changed_headers_malformed_rows_empty_tables_and_nul_refused(self):
        cases = [(MAP.replace(b"Addr", b"Other"), WHY), (MAP + b"not a map row\n", WHY),
                 (MAP, WHY.replace(b"reference", b"other")), (MAP, WHY + b"only\ttwo\n"),
                 (MAP, WHY.splitlines(True)[0]), (MAP, WHY + b"a\t\tb\n"),
                 (MAP + b"\0", WHY), (MAP, WHY + b"\0"), (b"", WHY)]
        for mapping, why in cases:
            with self.subTest(mapping=mapping[-20:], why=why[-20:]), self.assertRaises(ValueError):
                link.summarize(mapping, why)

    def test_byte_and_row_bounds_apply_before_indexing(self):
        with patch.object(link, "LIMIT", len(MAP) - 1):
            with self.assertRaisesRegex(ValueError, "oversized"):
                link.summarize(MAP, WHY)
        with self.assertRaisesRegex(ValueError, "row bound"):
            link.summarize(MAP, WHY + b"x" * 16385)

    def test_diagnostic_recipe_changes_only_one_argument(self):
        root = TOOLS.parents[1]
        original = (root / "compliance/evidence/graphviz-backend-reproduction/upstream-Dockerfile").read_bytes()
        plain = link.backend.derive_recipe(original, root)
        value = link.recipe(original, root)
        self.assertEqual(value.count(link.FLAG), 1)
        self.assertEqual(value.replace(link.FLAG, b""), plain)
        with self.assertRaisesRegex(ValueError, "Unexpected original"):
            link.recipe(original + b"RUN echo changed\n", root)

    def test_unexpected_parser_format_keeps_raw_sidecars_for_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output, built = root / "receipt", root / "built"
            output.mkdir(); built.mkdir()
            (output / "link-prepared.json").write_text(json.dumps({"fixture": True}))
            (built / "backend.js").write_bytes(b"owned comparison fixture")
            raw_map = MAP.replace(b"Addr", b"Unexpected")
            (built / "backend.map").write_bytes(raw_map)
            (built / "why-extract.tsv").write_bytes(WHY)
            # The ordinary backend/context verifier is tested separately. This
            # isolates preservation when the next, diagnostic-only parser fails.
            with patch.object(link, "descriptor", return_value={"fixture": True}), \
                 patch.object(link.backend, "compare", return_value={"backend_equal": True, "built_backend": {}}):
                with self.assertRaisesRegex(ValueError, "map header"):
                    link.compare(output, built)
            self.assertEqual((output / "backend.map").read_bytes(), raw_map)
            self.assertEqual((output / "why-extract.tsv").read_bytes(), WHY)
            self.assertFalse((output / "link-result.json").exists())


class CapturedGraphvizLinkTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        folder = self.root / proof.PACKET
        self.result = json.loads((folder / "result.json").read_text())
        self.raw_map = (folder / "backend.map").read_bytes()
        self.raw_why = (folder / "why-extract.tsv").read_bytes()

    def test_current_raw_sidecars_reproduce_complete_stage_qualified_index(self):
        value = proof.verify(self.root)
        self.assertEqual(value["status"], "passed")
        self.assertEqual(value["map_rows"], 9874)
        self.assertEqual(value["extraction_rows"], 577)
        self.assertEqual(value["mapped_archive_members"], 426)
        self.assertEqual(value["extracted_archive_members"], 457)

    def test_false_output_recipe_index_scope_identity_and_rights_claims_rejected(self):
        for kind in ("output", "boolean", "recipe", "index", "scope", "host", "extra"):
            value = copy.deepcopy(self.result)
            if kind == "output":
                value["built_backend"]["sha256"] = "a" * 64
            elif kind == "boolean":
                value["backend_equal"] = 1
            elif kind == "recipe":
                value["inputs"]["diagnostic_context"]["Dockerfile"]["sha256"] = "a" * 64
            elif kind == "index":
                value["index"]["extraction_rows"].pop()
            elif kind == "scope":
                value["scope"] = "complete final optimized retention and clearance"
            elif kind == "host":
                value["hosted"]["url"] = "https://example.invalid/receipt"
            else:
                value["source_offer_verified"] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                proof.validate(value, self.raw_map, self.raw_why, self.root)

    def test_changed_raw_map_or_extraction_data_rejected(self):
        for mapping, why in [(self.raw_map + b"\n", self.raw_why), (self.raw_map, self.raw_why + b"\n")]:
            with self.assertRaisesRegex(ValueError, "Raw diagnostic identity"):
                proof.validate(self.result, mapping, why, self.root)

    def test_coherent_but_malformed_diagnostic_rejected_by_parser(self):
        value = copy.deepcopy(self.result)
        mapping = self.raw_map.replace(b"Addr", b"Other", 1)
        value["sidecars"]["backend.map"] = link.backend.record(mapping)
        with self.assertRaisesRegex(ValueError, "map header"):
            proof.validate(value, mapping, self.raw_why, self.root)

    def test_raw_receipt_byte_pin_rejects_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / proof.PACKET
            folder.mkdir(parents=True)
            data = (self.root / proof.PACKET / "result.json").read_bytes()
            (folder / "result.json").write_bytes(data + b"\n")
            with self.assertRaisesRegex(ValueError, "Captured link receipt"):
                proof.verify(root)


if __name__ == "__main__":
    unittest.main()
