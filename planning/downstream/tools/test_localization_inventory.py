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

    def test_build_products_do_not_enter_source_catalog_inventory(self):
        repo = self.make_repo(self.fixture("valid.json"))
        build_catalog = repo / "MacDown2/Packages/MacDownKit/.build/debug/Mock.bundle/Localizable.xcstrings"
        build_catalog.parent.mkdir(parents=True)
        build_catalog.write_text(json.dumps(self.fixture("missing-placeholder.json")), encoding="utf-8")
        self.assertEqual(len(subject.catalog_paths(repo)), 1)
        self.assertEqual(subject.validate(repo), [])

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

    def test_top_level_plural_variants_are_inventoried_and_validated(self):
        key = "%lld preview errors"
        plural = {
            category: {"stringUnit": {"state": "needs_review", "value": text}}
            for category, text in {"one": "%lld preview error", "other": "%lld preview errors"}.items()
        }
        catalog = {"sourceLanguage": "en", "strings": {
            key: {"localizations": {"fr": {"variations": {"plural": plural}}}}
        }}
        repo = self.make_repo(catalog)
        localization = subject.load_catalog(repo / "MacDown2/MacDown2/Localizable.xcstrings")["strings"][key]["localizations"]["fr"]
        self.assertEqual(subject.variants(localization), {"value": ["one", "other"]})
        self.assertEqual(subject.localization_state(localization), "needs_review")
        self.assertEqual(subject.validate(repo), [])

        plural.pop("other")
        self.assertTrue(any("lacks an other variant" in error for error in subject.validate(self.make_repo(catalog))))
        plural["other"] = {"stringUnit": {"state": "needs_review", "value": "%@ preview errors"}}
        self.assertTrue(any("placeholders" in error for error in subject.validate(self.make_repo(catalog))))

    def test_malformed_top_level_plural_unit_is_a_controlled_catalog_error(self):
        key = "%lld preview errors"
        catalog = {"sourceLanguage": "en", "strings": {
            key: {"localizations": {"en": {"variations": {"plural": {
                "other": {"stringUnit": "invalid"}
            }}}}}
        }}
        with self.assertRaisesRegex(subject.CatalogError, "plural 'other' stringUnit is not an object"):
            subject.validate(self.make_repo(catalog))
        catalog["strings"][key]["localizations"]["en"]["variations"]["plural"]["other"] = {
            "stringUnit": None
        }
        with self.assertRaisesRegex(subject.CatalogError, "plural 'other' stringUnit is not an object"):
            subject.validate(self.make_repo(catalog))
        catalog["strings"][key]["localizations"]["en"]["variations"]["plural"]["other"] = {
            "stringUnit": {"value": 7}
        }
        with self.assertRaisesRegex(subject.CatalogError, "plural 'other' stringUnit.value is not a string"):
            subject.validate(self.make_repo(catalog))

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


class ProductPluralInventoryTests(unittest.TestCase):
    """Guard the current plural keys and expose, without approving, draft locale coverage."""

    repo = Path(__file__).resolve().parents[3]
    app_catalog = "MacDown2/MacDown2/Localizable.xcstrings"
    status_key = "%lld characters, %lld words"
    selected_key = "%lld selected"
    preview_budget_key = (
        "^[%lld valid placement](inflect: true) exceeded the preview budget "
        "and remain as authored source"
    )
    single_count_keys = {
        "%lld preview errors": "value",
        "%lld preview warnings": "value",
        "Exported with %lld issues": "arg1",
        "rendered output too large (%lld bytes)": "arg1",
        "…and %lld more issues.": "arg1",
    }
    categories = {
        "en": ["one", "other"],
        "fr": ["one", "other"],
        "ja": ["other"],
        "pl": ["few", "many", "one", "other"],
    }

    @staticmethod
    def contains_plural(value):
        if isinstance(value, dict):
            return "plural" in value or any(ProductPluralInventoryTests.contains_plural(child)
                                            for child in value.values())
        if isinstance(value, list):
            return any(ProductPluralInventoryTests.contains_plural(child) for child in value)
        return False

    def test_all_app_plural_keys_have_explicit_inventory_evidence(self):
        generated = {
            entry["key"]: entry
            for entry in subject.inventory(self.repo)["entries"]
            if entry["catalog"] == self.app_catalog and any(entry["variants"].values())
        }
        expected_keys = set(self.single_count_keys) | {
            self.status_key, self.selected_key, self.preview_budget_key
        }
        self.assertEqual(set(generated), expected_keys)
        declared = {
            (path.relative_to(self.repo).as_posix(), key)
            for path in self.repo.glob("MacDown2/**/*.xcstrings")
            for key, entry in json.loads(path.read_text(encoding="utf-8"))["strings"].items()
            if self.contains_plural(entry)
        }
        self.assertEqual(declared, {(self.app_catalog, key) for key in expected_keys})

        # Both counts select independently in every review locale. Draft
        # wording remains separate from this structural catalog assertion.
        expected_status = {
            locale: {"arg1": forms, "arg2": forms}
            for locale, forms in self.categories.items()
        }
        self.assertEqual(generated[self.status_key]["variants"], expected_status)
        expected_selected = {"en": {}}
        expected_selected.update({locale: {"value": self.categories[locale]} for locale in ("fr", "ja", "pl")})
        self.assertEqual(generated[self.selected_key]["variants"], expected_selected)
        expected_budget = {locale: {"arg1": self.categories[locale]} for locale in ("fr", "ja", "pl")}
        self.assertEqual(generated[self.preview_budget_key]["variants"], expected_budget)
        for key, substitution in self.single_count_keys.items():
            expected = {locale: {substitution: forms} for locale, forms in self.categories.items()}
            self.assertEqual(generated[key]["variants"], expected, key)

        tracked = json.loads((self.repo / "planning/downstream/mostlytext-localization-inventory.json")
                             .read_text(encoding="utf-8"))
        tracked_entries = {entry["key"]: entry for entry in tracked["entries"]
                           if entry["catalog"] == self.app_catalog and entry["key"] in expected_keys}
        self.assertEqual(set(tracked_entries), expected_keys)
        for key, entry in generated.items():
            self.assertEqual(tracked_entries[key]["variants"], entry["variants"], key)
            self.assertEqual(tracked_entries[key]["locale_states"], entry["locale_states"], key)
            self.assertNotIn("unknown", entry["locale_states"].values(), key)


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
