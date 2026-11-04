"""Offline controls for bounded, stage-qualified linker evidence."""

from pathlib import Path
import sys
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import capture_graphviz_link as link

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


if __name__ == "__main__":
    unittest.main()
