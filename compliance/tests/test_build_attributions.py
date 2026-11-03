"""Keep reviewed build notices and their limitations intact in ordinary CI."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_build_attributions as verify


class BuildAttributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = TOOLS.parents[1]
        manifest = json.loads((source / verify.MANIFEST).read_text())
        paths = [verify.MANIFEST, 'compliance/inventory.json',
                 'compliance/evidence/d2-0.1.33/source-graph.json',
                 'compliance/evidence/mermaid-11.17.2/module-notice-map.json',
                 'compliance/evidence/viz-js-3.30.0/source-audit.json']
        paths += [t['path'] for r in manifest['records'] for t in r['licence_texts']]
        for name in paths:
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, self.root / name)

    def test_committed_source_build_notices_pass(self):
        self.assertEqual(len(verify.verify_installed(self.root)['records']), 22)

    def test_corrupt_license_rejected(self):
        report = verify.verify_installed(self.root)
        text = report['records'][0]['licence_texts'][0]
        (self.root / text['path']).write_text('Incorrect replacement license')
        with self.assertRaisesRegex(ValueError, 'notice changed'):
            verify.verify_installed(self.root)

    def test_changing_source_graph_rejected(self):
        p = self.root / 'compliance/evidence/d2-0.1.33/source-graph.json'
        p.write_bytes(p.read_bytes() + b'\n')
        with self.assertRaisesRegex(ValueError, 'Source graph changed'):
            verify.verify_installed(self.root)

    def test_removing_freetype_credit_or_claiming_binary_proof_rejected(self):
        p = self.root / 'compliance/inventory.json'
        baseline = p.read_text()
        for change in ['credit', 'resolution', 'duplicate']:
            with self.subTest(change=change):
                inventory = json.loads(baseline)
                row = next(r for r in inventory['components'] if r['id'] == 'd2-build-github.com-golang-freetype')
                if change == 'credit':
                    row['copyright'].pop(1)
                elif change == 'resolution':
                    row['resolution'] = 'independently-rebuilt-and-binary-verified'
                else:
                    inventory['components'].append(row)
                p.write_text(json.dumps(inventory))
                with self.assertRaisesRegex(ValueError, 'differs from reviewed evidence'):
                    verify.verify_installed(self.root)

    def test_coherently_rewriting_manifest_and_inventory_rejected(self):
        for name in [verify.MANIFEST, 'compliance/inventory.json']:
            p = self.root / name
            p.write_text(p.read_text().replace('publisher-source-build-graph', 'exact-binary-proof'))
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            verify.verify_installed(self.root)

    def test_freetype_copyright_symbol_is_preserved(self):
        report = verify.verify_installed(self.root)
        row = next(r for r in report['records'] if r['id'] == 'd2-build-github.com-golang-freetype')
        text = next(t for t in row['licence_texts'] if t.get('source_encoding'))
        body = (self.root / text['path']).read_bytes()
        self.assertIn('copyright ©'.encode(), body)
        self.assertEqual(verify.sha(body.decode().encode('latin-1')), text['upstream_sha256'])


if __name__ == '__main__':
    unittest.main()
