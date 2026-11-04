import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('coverage', Path(__file__).with_name('compiled_string_coverage.py'))
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


class CompiledStringCoverageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / 'repo'
        self.extraction = Path(self.temporary.name) / 'extraction'
        self.extraction.mkdir()
        self.app = self.source('MacDown2/MacDown2/Label.swift')
        self.package = self.source('MacDown2/Packages/MacDownKit/Sources/Example/Label.swift')
        self.cli = self.source('MacDown2/MacDown2CLI/Main.swift')
        self.catalog('MacDown2/MacDown2/Localizable.xcstrings', ['App label'])
        self.catalog('MacDown2/Packages/MacDownKit/Sources/Example/Resources/Localizable.xcstrings', ['Value %d'])
        self.record(self.app, ['App label'])
        self.record(self.package, ['Value %d'])
        self.record(self.cli, [])

    def source(self, name):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('import Foundation\nlet example = 1\n')
        return path

    def catalog(self, name, keys):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {key: {} for key in keys}}))

    def record(self, source, keys, suffix='arm64'):
        path = self.extraction / f'{source.parent.name}-{source.stem}-{suffix}.stringsdata'
        path.write_text(json.dumps({'source': str(source), 'version': 1, 'tables': {
            'Localizable': [{'key': key, 'location': {'startingLine': 1}} for key in keys],
        }}))
        return path

    def test_complete_owned_extraction_passes_and_paths_are_relative(self):
        result = coverage.check(self.repo, self.extraction)
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['compiled_sources'], 3)
        self.assertEqual(result['catalogs'], 2)
        self.assertEqual(result['distinct_keys'], 2)
        self.assertTrue(all(not Path(row['source']).is_absolute() for row in result['routes']))

    def test_matching_architecture_duplicates_pass(self):
        self.record(self.app, ['App label'], 'x86_64')
        self.assertEqual(coverage.check(self.repo, self.extraction)['compiled_sources'], 3)

    def test_inconsistent_architecture_duplicates_refuse(self):
        self.record(self.app, ['Different label'], 'x86_64')
        with self.assertRaisesRegex(coverage.CoverageError, 'inconsistent architecture'):
            coverage.check(self.repo, self.extraction)

    def test_empty_extraction_refuses(self):
        for path in self.extraction.iterdir():
            path.unlink()
        with self.assertRaisesRegex(coverage.CoverageError, 'incomplete compiler extraction'):
            coverage.check(self.repo, self.extraction)

    def test_unextracted_no_key_source_still_refuses(self):
        self.record(self.cli, []).unlink()
        with self.assertRaisesRegex(coverage.CoverageError, 'Main.swift'):
            coverage.check(self.repo, self.extraction)

    def test_new_source_cannot_hide_in_partial_extraction(self):
        self.source('MacDown2/MacDown2/New.swift')
        with self.assertRaisesRegex(coverage.CoverageError, 'New.swift'):
            coverage.check(self.repo, self.extraction)

    def test_deleted_source_receipt_refuses(self):
        self.app.unlink()
        with self.assertRaisesRegex(coverage.CoverageError, 'missing owned source'):
            coverage.check(self.repo, self.extraction)

    def test_dependency_keys_do_not_belong_to_the_app(self):
        external = Path(self.temporary.name) / 'dependency.swift'
        self.record(external, ['Dependency text'])
        self.assertEqual(coverage.check(self.repo, self.extraction)['distinct_keys'], 2)

    def test_resource_script_is_not_a_compilation_input(self):
        self.source('MacDown2/Packages/MacDownKit/Sources/Example/Resources/script.swift')
        self.assertEqual(coverage.check(self.repo, self.extraction)['compiled_sources'], 3)

    def test_signed_integer_width_requires_the_exact_key(self):
        self.record(self.package, ['Value %lld'])
        result = coverage.check(self.repo, self.extraction)
        self.assertEqual(result['status'], 'missing-keys')
        self.assertEqual(result['missing'][0]['key'], 'Value %lld')

    def test_escaped_quotes_require_the_exact_key(self):
        self.record(self.app, ['"%@"'])
        self.catalog('MacDown2/MacDown2/Localizable.xcstrings', ['\\"%@\\"'])
        self.assertEqual(coverage.check(self.repo, self.extraction)['missing'][0]['key'], '"%@"')

    def test_unknown_owned_table_refuses(self):
        path = self.record(self.app, ['App label'])
        data = json.loads(path.read_text())
        data['tables'] = {'Other': data['tables']['Localizable']}
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(coverage.CoverageError, 'unknown table'):
            coverage.check(self.repo, self.extraction)

    def test_uncatalogued_module_cannot_emit_owned_keys(self):
        source = self.source('MacDown2/Packages/MacDownKit/Sources/Other/Label.swift')
        self.record(source, ['Owned new text'])
        with self.assertRaisesRegex(coverage.CoverageError, 'no owned string catalog'):
            coverage.check(self.repo, self.extraction)

    def test_malformed_compiler_json_refuses(self):
        self.record(self.app, []).write_text('{')
        with self.assertRaises(ValueError):
            coverage.check(self.repo, self.extraction)

    def test_invalid_compiler_location_refuses(self):
        path = self.record(self.app, ['App label'])
        data = json.loads(path.read_text())
        data['tables']['Localizable'][0]['location']['startingLine'] = True
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(coverage.CoverageError, 'malformed compiler location'):
            coverage.check(self.repo, self.extraction)

    def test_zero_keys_cannot_be_called_complete(self):
        for source in [self.app, self.package, self.cli]:
            self.record(source, [])
        with self.assertRaisesRegex(coverage.CoverageError, 'no owned localized keys'):
            coverage.check(self.repo, self.extraction)


if __name__ == '__main__':
    unittest.main()
