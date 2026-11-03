"""Real filesystem controls for complete app/installer resource verification."""
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_compliance import Fixture, compliance


class ArtifactLinkTests(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.app = self.fx.make_app().resolve()
        self.resources = self.app / 'Contents/Resources'
        self.outside = self.fx.root.resolve() / 'outside'
        self.outside.mkdir()
        (self.outside / 'unknown.js').write_text('unregistered();\n')

    def tearDown(self):
        self.fx.close()

    def errors(self, artifact=None):
        return self.fx.check(release=True, artifact=artifact or self.app).errors

    def fails(self, message, artifact=None):
        self.assertTrue(any(message in e for e in self.errors(artifact)), message)

    def test_external_file_alias_is_rejected_without_hashing_its_target(self):
        (self.resources / 'unknown.js').symlink_to('../../../../outside/unknown.js')
        original = compliance.sha256_file
        def bounded(path):
            self.assertNotEqual(path, self.outside / 'unknown.js')
            return original(path)
        with patch.object(compliance, 'sha256_file', side_effect=bounded):
            self.fails('unsafe artifact link: Contents/Resources/unknown.js')

    def test_external_directory_alias_is_rejected(self):
        (self.resources / 'escaped').symlink_to('../../../../outside', target_is_directory=True)
        self.fails('unsafe artifact link: Contents/Resources/escaped')

    def test_internal_script_alias_cannot_disguise_an_unknown_text_file(self):
        (self.resources / 'unknown.txt').write_text('unregistered();\n')
        (self.resources / 'unknown.js').symlink_to('unknown.txt')
        self.fails('unregistered runtime file: Contents/Resources/unknown.js')

    def test_registered_internal_alias_and_relative_chain_pass(self):
        (self.resources / 'known.txt').symlink_to('lib.js')
        (self.resources / 'known.js').symlink_to('known.txt')
        self.assertEqual(self.errors(), [])

    def test_framework_version_directory_links_pass(self):
        framework = self.app / 'Contents/Frameworks/Example.framework'
        (framework / 'Versions/A/Resources').mkdir(parents=True)
        (framework / 'Versions/A/Example').write_bytes(b'compiled fixture')
        (framework / 'Versions/Current').symlink_to('A', target_is_directory=True)
        (framework / 'Resources').symlink_to('Versions/Current/Resources', target_is_directory=True)
        (framework / 'Example').symlink_to('Versions/Current/Example')
        self.assertEqual(self.errors(), [])

    def test_broken_file_link_and_directory_cycle_are_rejected(self):
        (self.resources / 'broken.js').symlink_to('absent.js')
        (self.resources / 'cycle').symlink_to('cycle', target_is_directory=True)
        self.fails('unsafe artifact link: Contents/Resources/broken.js')
        self.fails('unsafe artifact link: Contents/Resources/cycle')

    def test_absolute_internal_link_is_not_a_portable_artifact(self):
        (self.resources / 'alias.js').symlink_to(self.resources / 'lib.js')
        self.fails('unsafe artifact link: Contents/Resources/alias.js')

    def test_intermediate_escape_returning_inside_is_still_rejected(self):
        (self.outside / 'back').symlink_to(self.resources, target_is_directory=True)
        (self.resources / 'alias.js').symlink_to('../../../../outside/back/lib.js')
        self.fails('unsafe artifact link: Contents/Resources/alias.js')

    def test_file_traversal_is_not_normalized_into_a_valid_alias(self):
        for target in ['lib.js/../lib.js', 'lib.js/.', 'lib.js/']:
            with self.subTest(target=target):
                alias = self.resources / 'invalid.js'
                alias.symlink_to(target)
                try:
                    self.fails('unsafe artifact link: Contents/Resources/invalid.js')
                finally:
                    alias.unlink()

    def test_resolver_rejects_escape_before_an_outside_component_lstat(self):
        (self.resources / 'escaped').symlink_to('../../../../outside/unknown.js')
        original = Path.lstat
        def bounded(path, *args, **kwargs):
            self.assertFalse(path.is_relative_to(self.outside))
            return original(path, *args, **kwargs)
        with patch.object(Path, 'lstat', bounded):
            self.fails('unsafe artifact link: Contents/Resources/escaped')

    def test_fifo_is_refused_without_opening_it(self):
        os.mkfifo(self.resources / 'pipe.js')
        self.fails('unsupported artifact object: Contents/Resources/pipe.js')

    def test_exact_installer_applications_shortcut_passes(self):
        stage = self.app.parent
        (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
        self.assertEqual(self.errors(stage), [])

    def test_app_level_and_fake_installer_shortcuts_fail(self):
        (self.app / 'Applications').symlink_to('/Applications', target_is_directory=True)
        self.fails('unsafe artifact link: Applications')
        (self.app.parent / 'Applications').symlink_to(self.outside, target_is_directory=True)
        self.fails('unsafe artifact link: Applications', self.app.parent)

    def test_supplied_root_alias_is_resolved_before_link_validation(self):
        alias = self.fx.root / 'app-alias'
        alias.symlink_to(self.app, target_is_directory=True)
        (self.resources / 'known.js').symlink_to('lib.js')
        self.assertEqual(self.errors(alias), [])

    def test_walk_failure_is_an_error_instead_of_an_empty_or_partial_success(self):
        original = compliance.os.walk
        def refused(top, *args, **kwargs):
            if Path(top) == self.app:
                kwargs.get('onerror', lambda e: None)(PermissionError('fixture scan refused'))
                return iter([])
            return original(top, *args, **kwargs)
        with patch.object(compliance.os, 'walk', side_effect=refused):
            self.fails('artifact directory unreadable')

    def test_file_read_failure_is_reported(self):
        original = compliance.sha256_file
        def refused(path):
            if path == self.resources / 'lib.js':
                raise PermissionError('fixture read refused')
            return original(path)
        with patch.object(compliance, 'sha256_file', side_effect=refused):
            self.fails('artifact file unreadable: Contents/Resources/lib.js')

    def test_non_directory_root_is_rejected(self):
        self.fails('artifact is not a directory', self.resources / 'lib.js')


if __name__ == '__main__':
    unittest.main()
