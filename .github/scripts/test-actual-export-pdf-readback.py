#!/usr/bin/env python3
"""Pure hostile evidence-admission controls; never execute PDFKit or a product."""
import gzip
import hashlib
import importlib.util
from pathlib import Path
from unittest.mock import patch
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('actual_pdf_readback', Path(__file__).with_name('read-actual-export-pdf.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class OriginalRecordAdmission(unittest.TestCase):
    def exercise(self, *, raw=b'owned original canary', declared=None, digest=None, name='original.gz', symlink=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = root / 'original.gz'
            actual.write_bytes(gzip.compress(raw, mtime=0))
            if symlink:
                target = root / 'redirect.gz'
                target.symlink_to(actual)
                name = target.name
            row = {'file': name, 'bytes': len(raw) if declared is None else declared,
                   'sha256': hashlib.sha256(raw).hexdigest() if digest is None else digest}
            with patch.object(probe, 'PACKET', root):
                return probe.decoded_record(row)

    def test_exact_record_is_admitted(self):
        self.assertEqual(self.exercise(), b'owned original canary')

    def test_redirect_and_absolute_names_are_refused(self):
        for name in ['../original.gz', '/tmp/original.gz']:
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                self.exercise(name=name)

    def test_symlink_is_refused(self):
        with self.assertRaises(RuntimeError):
            self.exercise(symlink=True)

    def test_byte_change_and_truncation_are_refused(self):
        with self.assertRaises(RuntimeError):
            self.exercise(digest='0' * 64)
        with self.assertRaises(RuntimeError):
            self.exercise(declared=5)

    def test_compressed_bomb_is_bounded_by_original_declared_size(self):
        with self.assertRaises(RuntimeError):
            self.exercise(raw=b'0' * 1_000_000, declared=1)


if __name__ == '__main__':
    unittest.main()
