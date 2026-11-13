"""Discriminating controls for the non-runtime #53 declaration checker."""

import copy
import tempfile
from pathlib import Path
import unittest

import check_legacy_preference_map as coverage


HEADER = b"""@interface MPPreferences : PAPreferences
@property (assign) BOOL editorSmartHome;
@property (assign) BOOL editorShowWordCount;
@property (assign) BOOL extensionStrikethough;
// Calculated values.
@property (readonly) NSString *editorBaseFontName;
// Convinience methods.
@property (nonatomic, assign) NSArray *filesToOpen;
@end
"""
IMPLEMENTATION = b"""@dynamic editorSmartHome;
@dynamic editorShowWordCount;
@dynamic extensionStrikethough;
"""


class DeclarationCoverageTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.repo = Path(self.folder.name)
        self.destination = "MacDown2/Packages/MacDownKit/Sources/AppSettings/EditorSettings.swift"
        path = self.repo / self.destination
        path.parent.mkdir(parents=True)
        path.write_text("public struct EditorSettings { public var smartHome: Bool; public var showsStatusBar: Bool }")
        self.record = {"schema": 1, "scope": "declaration_coverage_only", "migration_complete": False,
                       "legacy_source": {"header_sha256": coverage.sha(HEADER),
                                         "implementation_sha256": coverage.sha(IMPLEMENTATION)}, "entries": []}
        for key, declaration in coverage.declarations(HEADER.decode(), IMPLEMENTATION.decode()).items():
            disposition = {"stored": "unsupported_current_surface", "calculated": "derive_from_stored_value",
                           "transient": "never_replay"}[declaration["kind"]]
            self.record["entries"].append({"key": key, **declaration, "disposition": disposition,
                                           "rationale": "fixture", "owner": "#53", "implementation_status": "not_implemented"})
        self.candidate(self.record["entries"][0], "smartHome")

    def candidate(self, entry, field):
        entry.update(disposition="candidate_equivalent", destination_candidate="EditorSettings." + field,
                     destination_source=self.destination, semantic_verification="pending")

    def check(self, record=None, header=HEADER, implementation=IMPLEMENTATION):
        return coverage.validate_declarations(record or self.record, header, implementation, self.repo)

    def test_complete_fixture_passes_with_no_migration_claim(self):
        self.assertEqual(self.check()["kinds"], {"stored": 3, "calculated": 1, "transient": 1})

    def test_full_validator_still_requires_the_runtime_report(self):
        catalog = self.repo / "MacDown2/Packages/MacDownKit/Sources/AppSettings/LegacyPreferenceCatalog.swift"
        catalog.write_text('.init("editorSmartHome", .boolean, .mapped)')
        with self.assertRaisesRegex(ValueError, "runtime report declaration coverage mismatch"):
            coverage.validate(self.record, HEADER, IMPLEMENTATION, self.repo)

    def test_missing_known_key_fails(self):
        self.record["entries"].pop()
        with self.assertRaisesRegex(ValueError, "key coverage"):
            self.check()

    def test_duplicate_key_fails(self):
        self.record["entries"].append(copy.deepcopy(self.record["entries"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate disposition"):
            self.check()

    def test_correcting_legacy_misspelling_is_not_a_mapping(self):
        self.record["entries"][2]["key"] = "extensionStrikethrough"
        with self.assertRaisesRegex(ValueError, "key coverage"):
            self.check()

    def test_computed_and_transient_properties_cannot_be_stored_imports(self):
        for index in (3, 4):
            with self.subTest(index=index):
                record = copy.deepcopy(self.record)
                record["entries"][index]["kind"] = "stored"
                with self.assertRaisesRegex(ValueError, "classification"):
                    self.check(record)

    def test_word_count_cannot_map_to_status_bar(self):
        self.candidate(self.record["entries"][1], "showsStatusBar")
        with self.assertRaisesRegex(ValueError, "word-count"):
            self.check()

    def test_destination_must_exist_in_current_source(self):
        self.record["entries"][0]["destination_candidate"] = "EditorSettings.removedOption"
        with self.assertRaisesRegex(ValueError, "property absent"):
            self.check()

    def test_changed_source_bytes_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            self.check(header=HEADER + b"// different source\n")

    def test_new_dynamic_declaration_requires_an_explicit_disposition(self):
        header = HEADER.replace(b"// Calculated", b"@property (assign) BOOL newKey;\n// Calculated")
        implementation = IMPLEMENTATION + b"@dynamic newKey;\n"
        self.record["legacy_source"].update(header_sha256=coverage.sha(header), implementation_sha256=coverage.sha(implementation))
        with self.assertRaisesRegex(ValueError, "key coverage"):
            self.check(header=header, implementation=implementation)

    def test_unknown_disposition_cannot_pass(self):
        self.record["entries"][2]["disposition"] = "todo"
        with self.assertRaisesRegex(ValueError, "unclassified"):
            self.check()

    def test_coverage_is_not_migration_completion(self):
        self.record["migration_complete"] = True
        with self.assertRaisesRegex(ValueError, "migration completion"):
            self.check()


if __name__ == "__main__":
    unittest.main()
