import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import prepare_graphviz_offer as offer


class GraphvizOfferTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'review.tar.gz'
        self.bodies = {'README.txt': offer.LIMITS.encode(), 'upstream/source.tar.gz': b'captured archive'}

    def test_deterministic_review_archive_and_limits(self):
        first, second = offer.encode(self.bodies), offer.encode(dict(reversed(list(self.bodies.items()))))
        self.assertEqual(first, second)
        self.path.write_bytes(first)
        offer.verify_archive(self.path, self.bodies)
        self.assertIn(b'Not approved as the complete', self.bodies['README.txt'])

    def test_changed_or_missing_required_source_rejected(self):
        for contents in [dict(self.bodies, **{'upstream/source.tar.gz': b'wrong source'}), {'README.txt': b'no source'}]:
            self.path.write_bytes(offer.encode(contents))
            with self.assertRaises(ValueError):
                offer.verify_archive(self.path, self.bodies)

    def test_extra_and_traversal_names_rejected(self):
        for name in ['unexpected.txt', '../outside', '/absolute']:
            self.path.write_bytes(offer.encode(dict(self.bodies, **{name: b'extra'})))
            with self.assertRaisesRegex(ValueError, 'member set'):
                offer.verify_archive(self.path, self.bodies)

    def test_duplicate_member_rejected(self):
        with tarfile.open(self.path, 'w:gz') as archive:
            for name, body in list(self.bodies.items()) + [next(iter(self.bodies.items()))]:
                entry = tarfile.TarInfo(name)
                entry.size = len(body)
                archive.addfile(entry, io.BytesIO(body))
        with self.assertRaisesRegex(ValueError, 'duplicated'):
            offer.verify_archive(self.path, self.bodies)

    def test_symlink_substitution_rejected(self):
        with tarfile.open(self.path, 'w:gz') as archive:
            for name, body in self.bodies.items():
                entry = tarfile.TarInfo(name)
                entry.type = tarfile.SYMTYPE
                entry.linkname = '/etc/passwd'
                archive.addfile(entry)
        with self.assertRaisesRegex(ValueError, 'type or contents'):
            offer.verify_archive(self.path, self.bodies)


if __name__ == '__main__':
    unittest.main()
