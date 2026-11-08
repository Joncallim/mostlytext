"""Negative controls for the selected plain-String sink guard."""

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import plain_string_sink_audit as subject


class PlainStringSinkAuditTests(unittest.TestCase):
    def make_repo(self, relative: str, source: str) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = Path(temporary.name)
        path = repo / relative
        path.parent.mkdir(parents=True)
        path.write_text(source, encoding="utf-8")
        return repo

    def test_raw_appkit_panel_copy_is_discovered(self):
        repo = self.make_repo("MacDown2/MacDown2/Panel.swift",
                              'panel.message = "Uncatalogued guidance"\n')
        sites, _, _ = subject.scan(repo)
        self.assertEqual([(site["kind"], site["route"]) for site in sites],
                         [("appkit_property", "plain")])

    def test_package_error_and_localized_continuation_are_distinguished(self):
        repo = self.make_repo("MacDown2/Packages/MacDownKit/Sources/TextSearch/WorkspaceReplaceEngine.swift",
                              '.failed("Uncatalogued failure")\n'
                              '.failed(String(localized:\n'
                              '    "Catalogued failure", bundle: .module))\n')
        sites, _, _ = subject.scan(repo)
        self.assertEqual([(site["route"], site["literal"]) for site in sites],
                         [("plain", '"Uncatalogued failure"'),
                          ("localized", '"Catalogued failure"')])

    def test_multiline_appkit_message_uses_localized_route(self):
        repo = self.make_repo("MacDown2/MacDown2/Alert.swift",
                              'alert.informativeText = String(\n'
                              '    localized: """\n'
                              '    An actionable message.\n'
                              '    """\n'
                              ')\n')
        sites, _, _ = subject.scan(repo)
        self.assertEqual(len(sites), 1)
        self.assertEqual(sites[0]["route"], "localized")
        self.assertIn("An actionable message.", sites[0]["literal"])

    def test_reviewed_localized_route_rejects_plain_regression(self):
        relative = "MacDown2/MacDown2/Panel.swift"
        repo = self.make_repo(relative, 'panel.message = String(localized: "Safe guidance")\n')
        sites, hashes, _ = subject.scan(repo)
        ledger = repo / "ledger.json"
        ledger.write_text(json.dumps({"schema": 1, "scope": "selected_plain_string_sinks",
                                      "sites": sites, "source_sha256": hashes}), encoding="utf-8")
        self.assertEqual(subject.check(repo, ledger)["status"], "passed")
        (repo / relative).write_text('panel.message = "Safe guidance"\n', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "sink routes changed"):
            subject.check(repo, ledger)


if __name__ == "__main__":
    unittest.main()
