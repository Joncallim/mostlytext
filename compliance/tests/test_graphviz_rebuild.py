"""Offline refusal controls; no compiler, Docker, upstream execution or network."""

import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).resolve().parents[1] / "tools/rebuild_graphviz_backend.py"
SPEC = importlib.util.spec_from_file_location("graphviz_rebuild", TOOL)
rebuild = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rebuild)

RECIPE = b'''FROM emscripten/emsdk:5.0.7 AS graphviz
ADD "https://github.com/libexpat/libexpat/releases/download/R_2_8_4/expat-2.8.4.tar.gz" ./expat.tar.gz
ADD "https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/16.0.0/graphviz-16.0.0.tar.gz" ./graphviz.tar.gz
RUN echo fixture-configure
FROM emscripten/emsdk:5.0.7 AS viz
RUN echo fixture-link
FROM scratch AS export
'''
BACKEND = b"fixture backend; never executed\n"


def tar_bytes(entries):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w:gz") as archive:
        for name, content, kind in entries:
            info = tarfile.TarInfo(name)
            info.type = kind
            if kind == tarfile.REGTYPE:
                info.size = len(content)
                archive.addfile(info, io.BytesIO(content))
            else:
                info.linkname = "target"
                archive.addfile(info)
    return data.getvalue()


class GraphvizRebuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "repo"
        evidence = self.root / "compliance/evidence/viz-js-3.30.0"
        evidence.mkdir(parents=True)
        self.inputs = self.base / "inputs"
        self.inputs.mkdir()
        self.output = self.base / "output"
        self.built = self.base / "built"
        self.built.mkdir()
        (self.built / "backend.js").write_bytes(BACKEND)
        prefix = f"viz-js-{rebuild.REVISION}/packages/viz/backend/"
        files = {"Dockerfile": RECIPE, "viz.c": b"fixture C\n", "pre.js": b"fixture JS\n"}
        archives = {
            "viz-source-99da545.tar.gz": tar_bytes([(prefix + n, b, tarfile.REGTYPE) for n, b in files.items()]),
            "viz-3.30.0.tgz": tar_bytes([("package/lib/backend.js", BACKEND, tarfile.REGTYPE)]),
            "expat-2.8.4.tar.gz": b"fixture Expat archive; never executed",
            "graphviz-16.0.0.tar.gz": b"fixture Graphviz archive; never executed",
        }
        for name, data in archives.items():
            (self.inputs / name).write_bytes(data)
        self.audit = {
            "archives": {n: rebuild.record(b) for n, b in archives.items()},
            "build_source_sha256": {"packages/viz/backend/" + n: rebuild.sha(b) for n, b in files.items()},
            "backend_sha256": rebuild.sha(BACKEND), "shipped_bundle_sha256": "a" * 64,
        }
        (evidence / "source-audit.json").write_text(json.dumps(self.audit))
        p = patch.object(rebuild, "BACKEND_BYTES", len(BACKEND))
        p.start()
        self.addCleanup(p.stop)

    def prepare(self):
        return rebuild.prepare(self.inputs, self.output, self.root)

    def test_complete_output_match_and_difference_are_recorded(self):
        self.prepare()
        self.assertTrue(rebuild.compare(self.output, self.built, self.root)["backend_equal"])
        (self.built / "backend.js").write_bytes(BACKEND + b"different suffix")
        self.assertFalse(rebuild.compare(self.output, self.built, self.root)["backend_equal"])
        self.assertFalse(json.loads((self.output / "result.json").read_text())["backend_equal"])

    def test_changed_archive_fails_before_context_creation(self):
        p = self.inputs / "graphviz-16.0.0.tar.gz"
        p.write_bytes(p.read_bytes() + b"tampered")
        with self.assertRaisesRegex(ValueError, "Oversized|Archive differs"):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_unexpected_recipe_cannot_change_flags(self):
        with self.assertRaisesRegex(ValueError, "Unexpected original"):
            rebuild.derive_recipe(RECIPE + b"RUN echo changed-link-flags\n", self.root)
        actual = rebuild.derive_recipe(RECIPE, self.root)
        self.assertIn(b"RUN echo fixture-configure\n", actual)
        self.assertIn(b"RUN echo fixture-link\n", actual)
        self.assertEqual(actual.count(rebuild.IMAGE.encode()), 2)

    def test_duplicate_link_oversized_and_unsafe_selected_members(self):
        cases = [
            ([("selected", b"one", tarfile.REGTYPE), ("selected", b"two", tarfile.REGTYPE)], "selected"),
            ([("selected", b"", tarfile.SYMTYPE)], "selected"),
            ([("selected", b"", tarfile.LNKTYPE)], "selected"),
            ([("selected", b"x" * (rebuild.MAX_MEMBER + 1), tarfile.REGTYPE)], "selected"),
            ([("../selected", b"one", tarfile.REGTYPE)], "../selected"),
            ([("/selected", b"one", tarfile.REGTYPE)], "/selected"),
        ]
        for entries, name in cases:
            with self.subTest(name=name, kind=entries[0][2]):
                with tarfile.open(fileobj=io.BytesIO(tar_bytes(entries))) as archive:
                    with self.assertRaises(ValueError):
                        rebuild.selected_member(archive, name)

    def test_no_overwrite_or_checkout_scratch(self):
        self.prepare()
        (self.output / "owner-file").write_text("preserve")
        with self.assertRaises(FileExistsError):
            self.prepare()
        self.assertEqual((self.output / "owner-file").read_text(), "preserve")
        with self.assertRaisesRegex(ValueError, "outside the checkout"):
            rebuild.prepare(self.inputs, self.root / "probe", self.root)

    def test_extra_context_changed_sources_and_fabricated_receipt_rejected(self):
        self.prepare()
        p = self.output / "context/extra"
        p.write_text("unreviewed context")
        with self.assertRaisesRegex(ValueError, "context members"):
            rebuild.compare(self.output, self.built, self.root)
        p.unlink()
        p = self.output / "context/viz.c"
        before = p.read_bytes()
        p.write_bytes(before + b"changed")
        with self.assertRaisesRegex(ValueError, "Context source differs"):
            rebuild.compare(self.output, self.built, self.root)
        p.write_bytes(before)
        p = self.output / "prepared.json"
        value = json.loads(p.read_text())
        value["expected_backend"]["sha256"] = "b" * 64
        p.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "receipt differs"):
            rebuild.compare(self.output, self.built, self.root)

    def test_output_links_and_oversize_rejected_without_reading(self):
        self.prepare()
        p = self.built / "backend.js"
        p.unlink()
        p.symlink_to(self.inputs / "viz-3.30.0.tgz")
        with self.assertRaisesRegex(ValueError, "regular file"):
            rebuild.compare(self.output, self.built, self.root)
        p.unlink()
        p.write_bytes(b"x" * (rebuild.MAX_MEMBER + 1))
        with self.assertRaisesRegex(ValueError, "Oversized"):
            rebuild.compare(self.output, self.built, self.root)


if __name__ == "__main__":
    unittest.main()
