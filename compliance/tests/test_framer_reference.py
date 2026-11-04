"""Refuse incomplete terms and dishonest original-version claims."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_framer_reference as framer


class FramerReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in [framer.NOTICE, 'compliance/inventory.json',
                     *[framer.PACKET + '/' + n for n in ['reference.json', 'mapping.json', 'helper-block.coffee']]]:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(TOOLS.parents[1] / name, target)

    def test_actual_complete_mit_text_and_qualified_attribution_pass(self):
        framer.verify_installed(self.root)
        self.assertIn(b'Copyright (c) 2014 Koen Bok', (self.root / framer.NOTICE).read_bytes())
        self.assertIn('original adaptation revision unspecified', framer.component()['resolution'])

    def test_missing_author_or_changed_terms_cannot_pass(self):
        path = self.root / framer.NOTICE
        original = path.read_bytes()
        for body in [original.replace(b'Copyright (c) 2014 Koen Bok', b''), original + b'New condition\n']:
            path.write_bytes(body)
            with self.assertRaisesRegex(ValueError, 'MIT text changed'):
                framer.verify_installed(self.root)

    def test_coherent_notice_inventory_change_cannot_substitute_terms(self):
        path = self.root / framer.NOTICE
        path.write_bytes(path.read_bytes() + b'Changed\n')
        ip = self.root / 'compliance/inventory.json'
        inventory = json.loads(ip.read_text())
        next(c for c in inventory['components'] if c['id'] == framer.ID)['licence_texts'][0]['sha256'] = framer.sha(path.read_bytes())
        ip.write_text(json.dumps(inventory))
        with self.assertRaises(ValueError):
            framer.verify_installed(self.root)

    def test_original_version_promotion_missing_or_duplicate_records_refuse(self):
        ip = self.root / 'compliance/inventory.json'
        baseline = json.loads(ip.read_text())
        for kind in ['original', 'missing', 'duplicate']:
            inventory = copy.deepcopy(baseline)
            component = next(c for c in inventory['components'] if c['id'] == framer.ID)
            if kind == 'original':
                component['resolution'] = 'exact original input'
            elif kind == 'missing':
                inventory['components'].remove(component)
            else:
                inventory['components'].append(component)
            ip.write_text(json.dumps(inventory))
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, 'attribution differs'):
                framer.verify_installed(self.root)

    def test_changed_mapping_or_source_reference_refuses(self):
        for name in ['mapping.json', 'reference.json']:
            p = self.root / framer.PACKET / name
            original = p.read_bytes()
            p.write_bytes(original + b' ')
            with self.subTest(name=name), self.assertRaises(ValueError):
                framer.verify_installed(self.root)
            p.write_bytes(original)

    def test_helper_arithmetic_identifier_comment_and_missing_end_refuse(self):
        original = (self.root / framer.PACKET / 'helper-block.coffee').read_text()
        for altered in [original.replace('1.0/6.0', '1.0/7.0'), original.replace('state.tension', 'state.stiffness'),
                        original + '\n\treturn state', original.replace('return - state.tension', '# comment\n\treturn - state.tension')]:
            with self.subTest(body=altered[:30]), self.assertRaises(ValueError):
                framer.helper_block(altered)
        self.assertEqual(framer.helper_block(original), framer.helper_block(original.replace('\t', '    ')))

    def test_every_spring_probe_requires_generated_code_not_just_comments(self):
        lines = [0, 1, 2, 3]
        span = {framer.ID: {'first_line': 0, 'end_line_exclusive': 5, 'probe_lines': lines}}
        positions = [(0, i, 7, line, 0) for i, line in enumerate(lines)]
        self.assertEqual(framer.fragment_references(positions, 7, span)[framer.ID]['generated_references'], 4)
        for dropped in lines:
            with self.subTest(dropped=dropped), self.assertRaisesRegex(ValueError, 'Every specific'):
                framer.fragment_references([p for p in positions if p[3] != dropped], 7, span)
        with self.assertRaisesRegex(ValueError, 'Every credited'):
            framer.fragment_references([(0, 0, 8, 0, 0)], 7, span)

    def test_missing_proof_does_not_qualify(self):
        (self.root / framer.PACKET / 'mapping.json').unlink()
        with self.assertRaises(FileNotFoundError):
            framer.verify_installed(self.root)


if __name__ == '__main__':
    unittest.main()
