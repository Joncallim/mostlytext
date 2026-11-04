"""Exercise malformed registration and actual packaging-path failures."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).with_name('verify-document-metadata.py'))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class DocumentMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / 'MacDown2.app'
        self.info = {'CFBundleIdentifier': 'app.mostlytext.MostlyText', 'CFBundleDisplayName': 'MostlyText',
                     'CFBundleExecutable': 'MacDown2', 'CFBundleDocumentTypes': [
                         {'CFBundleTypeRole': 'Editor', 'LSHandlerRank': 'Default', 'LSItemContentTypes': ['net.daringfireball.markdown']},
                         {'CFBundleTypeRole': 'Editor', 'LSHandlerRank': 'Alternate', 'LSItemContentTypes': ['public.source-code']}]}
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / metadata.RESOURCES).mkdir(parents=True)
        for name, body in [('MacDown2', b'app'), ('mostlytext-cli', b'command')]:
            path = self.app / 'Contents/MacOS' / name
            path.write_bytes(body)
            path.chmod(0o755)
        self.standalone = self.root / 'mostlytext'
        self.standalone.write_bytes(b'command')
        self.standalone.chmod(0o755)
        self.guide = self.root / 'guide.md'
        self.guide.write_text('"$APP_BUNDLE/Contents/MacOS/mostlytext-cli" --help\n')
        self.save_info()

    def save_info(self):
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_valid_compiled_shape_and_helper_binding_pass(self):
        self.assertEqual(metadata.verify(self.app, self.guide, self.standalone)['document_declarations'], 2)

    def test_editor_is_not_a_handler_rank(self):
        self.info['CFBundleDocumentTypes'][1]['LSHandlerRank'] = 'Editor'
        with self.assertRaisesRegex(ValueError, 'unsupported'):
            metadata.validate_info(self.info)

    def test_public_markdown_must_not_claim_ownership(self):
        self.info['CFBundleDocumentTypes'][0]['LSHandlerRank'] = 'Owner'
        with self.assertRaisesRegex(ValueError, 'must not claim Owner'):
            metadata.validate_info(self.info)

    def test_wrong_role_missing_markdown_and_duplicate_declarations_fail(self):
        for change in ['role', 'missing', 'duplicate']:
            with self.subTest(change=change):
                info = plistlib.loads(plistlib.dumps(self.info))
                if change == 'role': info['CFBundleDocumentTypes'][0]['CFBundleTypeRole'] = 'Default'
                elif change == 'missing': info['CFBundleDocumentTypes'].pop(0)
                else: info['CFBundleDocumentTypes'].append(info['CFBundleDocumentTypes'][0])
                with self.assertRaises(ValueError): metadata.validate_info(info)

    def test_missing_or_symlinked_helper_fails(self):
        path = self.app / metadata.HELPER
        path.unlink()
        with self.assertRaises(FileNotFoundError): metadata.verify(self.app)
        path.symlink_to(self.standalone)
        with self.assertRaisesRegex(ValueError, 'regular'): metadata.verify(self.app)

    def test_helper_must_not_be_the_app_binary(self):
        path = self.app / metadata.HELPER
        path.write_bytes(b'app')
        with self.assertRaisesRegex(ValueError, 'aliases'): metadata.verify(self.app)

    def test_public_command_and_embedded_copy_must_match(self):
        self.standalone.write_bytes(b'wrong build')
        with self.assertRaisesRegex(ValueError, 'differs'): metadata.verify(self.app, standalone=self.standalone)

    def test_guide_wrong_embedded_path_is_rejected(self):
        self.guide.write_text('"$APP_BUNDLE/Contents/MacOS/mostlytext" --help\n')
        with self.assertRaisesRegex(ValueError, 'guide examples'): metadata.verify(self.app, guide=self.guide)

    def test_missing_resource_bundle_is_rejected(self):
        (self.app / metadata.RESOURCES).rmdir()
        with self.assertRaisesRegex(ValueError, 'resource bundle'): metadata.verify(self.app)


if __name__ == '__main__':
    unittest.main()
