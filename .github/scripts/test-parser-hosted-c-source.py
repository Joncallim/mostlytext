#!/usr/bin/env python3
"""Pure refusal controls for the immutable hosted C-source input."""

import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("parser_c", HERE / "prepare-parser-hosted-c-source.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ParserCArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.graph = Path(sys.argv[1]).resolve()

    def test_qualified_artifact_is_exact(self):
        receipt = module.validate_artifact(self.graph)
        self.assertEqual(receipt["status"], "qualified")
        self.assertEqual(receipt["checkout"], module.GRAPH_CHECKOUT)

    def test_mutated_lock_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            graph = Path(folder)
            shutil.copytree(self.graph, graph, dirs_exist_ok=True)
            lock = graph / "Packages/MacDownKit/Package.resolved"
            lock.write_bytes(lock.read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "artifact changed"):
                module.validate_artifact(graph)

    def test_mutated_receipt_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            graph = Path(folder)
            shutil.copytree(self.graph, graph, dirs_exist_ok=True)
            receipt = graph / "receipt.json"
            receipt.write_bytes(receipt.read_bytes().replace(b'"qualified"', b'"failed"'))
            with self.assertRaisesRegex(ValueError, "artifact changed"):
                module.validate_artifact(graph)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
