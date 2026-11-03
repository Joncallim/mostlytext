import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_esbuild_runtime_notice as runtime


class EsbuildRuntimeNoticeTests(unittest.TestCase):
    def test_reviewed_formatting_only_correspondence(self):
        runtime.match_helper('var fn = (x) => { return x || 0; };',
                             'export var fn=(x)=>{\n// explained\nreturn x||0\n}')

    def test_operator_or_property_change_is_not_formatting(self):
        original = 'var fn = (x) => { return x.value || 0; };'
        for changed in ['var fn=(x)=>{return x.value && 0}', 'var fn=(x)=>{return x.other || 0}']:
            with self.assertRaisesRegex(ValueError, 'correspondence changed'):
                runtime.match_helper(original, changed)

    def test_strings_and_escapes_are_outside_reviewed_subset(self):
        for value in ["var x = 'value'", 'var x = "value"', 'var x = `value`', 'var x=\\u0061', 'var x=/abc/', 'var f=()=>{return\n0}']:
            with self.assertRaisesRegex(ValueError, 'outside reviewed helper subset'):
                runtime.helper_tokens(value)

    def test_ambiguous_or_reversed_boundaries_reject(self):
        for source in ['start body start end', 'end body start', 'start body']:
            with self.assertRaises(ValueError):
                runtime.select(source, 'start', 'end')

    def test_actual_distribution_keeps_qualified_identity(self):
        runtime.verify_installed(TOOLS.parents[1])
        c = runtime.component()
        self.assertNotIn('npm', c)
        self.assertIn('unresolved', c['version'])

    def test_exact_version_promotion_and_changed_notice_reject(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ['compliance/inventory.json', runtime.LICENSE_PATH]:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(TOOLS.parents[1] / name, p)
            ip = root / 'compliance/inventory.json'
            original = ip.read_bytes()
            inv = json.loads(original)
            row = next(c for c in inv['components'] if c['id'] == runtime.ID)
            row['npm'] = 'esbuild@0.27.7'
            row['version'] = '0.27.7'
            ip.write_text(json.dumps(inv))
            with self.assertRaisesRegex(ValueError, 'Qualified runtime attribution changed'):
                runtime.verify_installed(root)
            ip.write_bytes(original)
            p = root / runtime.LICENSE_PATH
            p.write_bytes(p.read_bytes() + b'altered terms')
            with self.assertRaisesRegex(ValueError, 'MIT text changed'):
                runtime.verify_installed(root)


if __name__ == '__main__':
    unittest.main()
