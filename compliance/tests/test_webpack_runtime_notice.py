"""Whole-source and emitted-operation controls for the qualified Webpack notice."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_webpack_runtime_notice as runtime


class WebpackRuntimeNoticeTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.raw = (self.root / runtime.PACKET / 'reference-map.json').read_bytes()
        self.mapping = json.loads((self.root / runtime.PACKET / 'mapping.json').read_text())

    def test_actual_distribution_preserves_qualified_reference_and_full_mit(self):
        runtime.verify_installed(self.root)
        self.assertNotIn('npm', runtime.component())
        self.assertIn('unresolved', runtime.component()['version'])

    def test_changed_real_helper_operation_is_not_a_complete_match(self):
        body = runtime.reference_bodies(self.raw)['hasOwnProperty%20shorthand']
        with self.assertRaisesRegex(ValueError, 'source content differs'):
            runtime.match_complete(body.replace('.call(', '.apply('), body)

    def test_formatting_is_not_silently_normalized(self):
        body = runtime.reference_bodies(self.raw)['bootstrap']
        with self.assertRaisesRegex(ValueError, 'no normalization'):
            runtime.match_complete(body + '\n', body)

    def test_source_list_without_body_operation_is_insufficient(self):
        self.mapping['helpers'][0]['generated_body_probe_references'] = 0
        with self.assertRaisesRegex(ValueError, 'body operation'):
            runtime.validate_mapping(self.mapping)

    def test_missing_helper_and_changed_body_reject(self):
        for kind in ['missing', 'body']:
            data = copy.deepcopy(self.mapping)
            if kind == 'missing':
                data['helpers'].pop()
            else:
                data['helpers'][0]['body_sha256'] = '0' * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                runtime.validate_mapping(data)

    def test_matching_reference_cannot_claim_the_original_emitter(self):
        self.mapping['original_emitter_version'] = '5.88.2'
        with self.assertRaisesRegex(ValueError, 'binding changed'):
            runtime.validate_mapping(self.mapping)

    def test_notice_alone_does_not_authorize_a_different_current_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ['compliance/inventory.json', runtime.LICENSE_PATH]:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self.root / name, target)
            bundle = root / 'MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js'
            bundle.parent.mkdir(parents=True)
            bundle.write_bytes(b'changed current runtime')
            with self.assertRaisesRegex(ValueError, 'Current shipped Mermaid'):
                runtime.verify_installed(root)

    def test_whole_package_claim_and_lost_copyright_reject(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ['compliance/inventory.json', runtime.LICENSE_PATH]:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self.root / name, path)
            ip = root / 'compliance/inventory.json'
            original = ip.read_bytes()
            value = json.loads(original)
            row = next(item for item in value['components'] if item['id'] == runtime.ID)
            row.update(npm='webpack@5.88.2', version='5.88.2')
            ip.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, 'Qualified Webpack'):
                runtime.verify_installed(root)
            ip.write_bytes(original)
            notice = root / runtime.LICENSE_PATH
            notice.write_bytes(notice.read_bytes().split(b'\n', 1)[1])
            with self.assertRaisesRegex(ValueError, 'MIT text changed'):
                runtime.verify_installed(root)


if __name__ == '__main__':
    unittest.main()
