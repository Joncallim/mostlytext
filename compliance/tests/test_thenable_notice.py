import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_thenable_notice as thenable


class ThenableNoticeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in [thenable.TERMS, thenable.NOTICE, 'compliance/inventory.json']:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(TOOLS.parents[1] / name, p)

    def test_current_notice_preserves_author_and_exact_standard_paragraphs(self):
        thenable.verify_installed(self.root)
        terms = (self.root / thenable.TERMS).read_bytes()
        notice = (self.root / thenable.NOTICE).read_bytes()
        self.assertIn(thenable.COPYRIGHT.encode(), notice)
        self.assertTrue(notice.endswith(terms))
        self.assertNotIn(b'<COPYRIGHT HOLDER>', notice)

    def test_changed_standard_terms_rejected(self):
        p = self.root / thenable.TERMS
        p.write_bytes(p.read_bytes().replace(b'permission notice', b'changed condition'))
        with self.assertRaisesRegex(ValueError, 'MIT terms changed'):
            thenable.verify_installed(self.root)

    def test_missing_author_in_distributed_notice_rejected(self):
        p = self.root / thenable.NOTICE
        p.write_bytes(p.read_bytes().replace(thenable.COPYRIGHT.encode(), b''))
        with self.assertRaisesRegex(ValueError, 'notice differs'):
            thenable.verify_installed(self.root)

    def test_coherently_changed_notice_and_inventory_hash_rejected(self):
        p = self.root / thenable.NOTICE
        p.write_bytes(p.read_bytes() + b'Altered terms\n')
        ip = self.root / 'compliance/inventory.json'
        inventory = json.loads(ip.read_text())
        row = next(r for r in inventory['components'] if r['id'] == thenable.ID)
        row['licence_texts'][0]['sha256'] = hashlib.sha256(p.read_bytes()).hexdigest()
        ip.write_text(json.dumps(inventory))
        with self.assertRaisesRegex(ValueError, 'attribution differs'):
            thenable.verify_installed(self.root)

    def test_fabricated_upstream_license_file_and_duplicate_record_rejected(self):
        ip = self.root / 'compliance/inventory.json'
        baseline = ip.read_text()
        for kind in ['filename', 'duplicate']:
            with self.subTest(kind=kind):
                inventory = json.loads(baseline)
                row = next(r for r in inventory['components'] if r['id'] == thenable.ID)
                if kind == 'filename':
                    row['licence_texts'][0]['upstream_path'] = 'LICENSE'
                else:
                    inventory['components'].append(row)
                ip.write_text(json.dumps(inventory))
                with self.assertRaisesRegex(ValueError, 'attribution differs'):
                    thenable.verify_installed(self.root)


if __name__ == '__main__':
    unittest.main()
