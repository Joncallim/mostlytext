#!/usr/bin/env python3
"""Pure source and lock contract checks for parser graph resolution."""

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location("parser_graph", HERE / "resolve-parser-hosted-graph.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ParserGraphTests(unittest.TestCase):
    def setUp(self):
        self.original = json.loads((ROOT / module.PACKAGE / "Package.resolved").read_text())

    def proposed(self):
        result = copy.deepcopy(self.original)
        for row in result["pins"]:
            if row["identity"] in module.NEW:
                row["state"]["revision"] = module.NEW[row["identity"]][1]
        result["originHash"] = "hosted-resolver-will-supply-this-value"
        return result

    def test_exact_three_revisions_are_the_only_allowed_lock_changes(self):
        self.assertEqual(module.verify_new_lock(self.original, self.proposed()),
                         {identity: value[1] for identity, value in module.NEW.items()})

    def test_unrelated_pin_change_is_refused(self):
        changed = self.proposed()
        row = next(row for row in changed["pins"] if row["identity"] == "textual")
        row["state"]["revision"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "Unreviewed resolved pin change: textual"):
            module.verify_new_lock(self.original, changed)

    def test_duplicate_owner_pin_is_refused(self):
        changed = self.proposed()
        changed["pins"][0]["identity"] = changed["pins"][1]["identity"]
        with self.assertRaisesRegex(ValueError, "24 unique"):
            module.verify_new_lock(self.original, changed)

    def test_temporary_manifests_change_only_the_reviewed_revisions(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source"
            staged = Path(folder) / "staged"
            for relative in [module.PACKAGE / "Package.swift", module.MARKDOWN / "Package.swift"]:
                destination = source / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes((ROOT / relative).read_bytes())
                target = staged / relative.relative_to("MacDown2/Packages")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(destination.read_bytes())
            module.stage_manifests(source, staged)
            package = (staged / "MacDownKit/Package.swift").read_text()
            markdown = (staged / "TreeSitterMarkdown/Package.swift").read_text()
            self.assertEqual(package.count(module.NEW["swifttreesitter"][1]), 1)
            self.assertEqual(package.count(module.NEW["neon"][1]), 1)
            self.assertEqual(markdown.count(module.NEW["swifttreesitter"][1]), 1)
            self.assertNotIn(module.OLD["swifttreesitter"][1], package + markdown)
            self.assertNotIn(module.OLD["neon"][1], package)


if __name__ == "__main__":
    unittest.main()
