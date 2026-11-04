"""Hermetic negative controls for the XCStrings inventory validator."""

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import localization_inventory as subject


class LocalizationInventoryTests(unittest.TestCase):
    fixtures = Path(__file__).parent / "fixtures/localization"

    def fixture(self, name):
        return json.loads((self.fixtures / name).read_text(encoding="utf-8"))

    def make_repo(self, catalog):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = Path(temporary.name)
        path = repo / "MacDown2/MacDown2/Localizable.xcstrings"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(catalog), encoding="utf-8")
        return repo

    def test_valid_catalog_passes(self):
        self.assertEqual(subject.validate(self.make_repo(self.fixture("valid.json"))), [])

    def test_missing_placeholder_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("missing-placeholder.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_extra_placeholder_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("extra-placeholder.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_type_mismatched_placeholder_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("type-mismatch.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_positional_identity_type_mismatch_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("positional-type-mismatch.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_positional_reordering_with_matching_types_passes(self):
        self.assertEqual(subject.validate(self.make_repo(self.fixture("positional-reordered-valid.json"))), [])

    def test_plural_without_other_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("plural-without-other.json")))
        self.assertTrue(any("lacks an other variant" in error for error in errors))

    def test_plural_type_mismatch_fails(self):
        catalog = self.fixture("plural-without-other.json")
        catalog["strings"]["%lld file"]["localizations"]["fr"]["substitutions"]["files"]["variations"]["plural"]["other"] = {"stringUnit": {"value": "%files fichiers"}}
        catalog["strings"]["%lld file"]["localizations"]["fr"]["substitutions"] = {
            "files": {"argNum": 1, "formatSpecifier": "@", "variations": {"plural": {"other": {"stringUnit": {"value": "%files fichiers"}}}}}
        }
        errors = subject.validate(self.make_repo(catalog))
        self.assertTrue(any("substitution types" in error for error in errors))

    def test_malformed_catalog_is_rejected(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = Path(temporary.name)
        path = repo / "MacDown2/MacDown2/Localizable.xcstrings"
        path.parent.mkdir(parents=True)
        path.write_text((self.fixtures / "malformed.json").read_text(encoding="utf-8"), encoding="utf-8")
        with self.assertRaisesRegex(subject.CatalogError, "malformed JSON"):
            subject.inventory(repo)

    def test_malformed_shapes_are_controlled_catalog_errors(self):
        for fixture, shape in [
            ("malformed-substitutions-array.json", "substitutions"),
            ("malformed-stringunit-value.json", "stringUnit.value"),
            ("malformed-variations-array.json", "variations"),
        ]:
            with self.subTest(fixture=fixture):
                repo = self.make_repo(self.fixture(fixture))
                with self.assertRaisesRegex(subject.CatalogError, shape):
                    subject.inventory(repo)

    def test_substitution_arg_num_must_be_a_positive_non_boolean_integer(self):
        for fixture in ["malformed-argnum-true.json", "malformed-argnum-zero.json", "malformed-argnum-negative.json"]:
            with self.subTest(fixture=fixture):
                with self.assertRaisesRegex(subject.CatalogError, "argNum must be a positive integer"):
                    subject.inventory(self.make_repo(self.fixture(fixture)))

    def test_printf_position_zero_is_rejected_in_source_and_translation(self):
        for fixture in ["zero-position-source.json", "zero-position-translation.json"]:
            with self.subTest(fixture=fixture):
                with self.assertRaisesRegex(subject.CatalogError, "positions are 1-based"):
                    subject.validate(self.make_repo(self.fixture(fixture)))


class TranslationResourceTests(unittest.TestCase):
    catalog = "MacDown2/MacDown2/Localizable.xcstrings"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        path = self.root / self.catalog
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"sourceLanguage": "en", "strings": {}, "version": "1.0"}))
        (self.root / ".tx").mkdir()
        self.config = ("[main]\nhost = https://www.transifex.com\n"
                       "[o:placeholder:p:placeholder:r:app]\n"
                       f"source_file = {self.catalog}\nfile_filter = {self.catalog}\n"
                       "source_lang = en\ntype = XCSTRINGS\n")

    def check(self, text):
        (self.root / ".tx/config").write_text(text)
        return subject.validate_translation_resources(self.root)

    def test_complete_source_mapping_passes_without_claiming_remote_setup(self):
        self.assertEqual(self.check(self.config), [])

    def test_missing_configuration_and_catalog_mapping_fail(self):
        self.assertTrue(subject.validate_translation_resources(self.root))
        self.assertTrue(any("missing translation resource" in e for e in self.check("[main]\n")))

    def test_duplicate_alias_to_one_catalog_fails(self):
        duplicate = self.config.split("[o:placeholder:p:placeholder:r:app]")[1]
        self.assertTrue(any("duplicate" in e for e in self.check(self.config + "[o:placeholder:p:placeholder:r:alias]" + duplicate)))

    def test_unknown_external_and_traversal_paths_fail(self):
        for source in ["/outside.xcstrings", "../outside.xcstrings", "MacDown2/Missing.xcstrings"]:
            with self.subTest(source=source):
                errors = self.check(self.config.replace(self.catalog, source))
                self.assertTrue(any("not a known catalog" in e for e in errors))

    def test_filter_type_and_language_mismatches_fail(self):
        for old, new, expected in [(f"file_filter = {self.catalog}", "file_filter = elsewhere", "file_filter"),
                                    ("type = XCSTRINGS", "type = STRINGS", "type"),
                                    ("source_lang = en", "source_lang = fr", "source_lang")]:
            with self.subTest(expected=expected):
                self.assertTrue(any(expected in e for e in self.check(self.config.replace(old, new))))

    def test_duplicate_section_is_controlled_configuration_error(self):
        self.assertTrue(any("invalid" in e for e in self.check(self.config + self.config)))
        (self.root / ".tx/config").write_bytes(b"\xff")
        self.assertTrue(any("invalid" in e for e in subject.validate_translation_resources(self.root)))

    def test_catalog_source_language_must_be_a_nonempty_string(self):
        for value in [None, "", True]:
            with self.subTest(value=value):
                (self.root / self.catalog).write_text(json.dumps({"sourceLanguage": value, "strings": {}}))
                (self.root / ".tx/config").write_text(self.config)
                with self.assertRaisesRegex(subject.CatalogError, "sourceLanguage"):
                    subject.validate_translation_resources(self.root)


if __name__ == "__main__":
    unittest.main()
