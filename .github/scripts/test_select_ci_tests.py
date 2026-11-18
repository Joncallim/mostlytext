"""Guard the CI selector against dropping dependent or unknown test suites."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("select-ci-tests.py")
SPEC = importlib.util.spec_from_file_location("select_ci_tests", SCRIPT)
SELECTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SELECTOR)


class SelectionTests(unittest.TestCase):
    manifest = {"targets": [
        {"name": "D2Rendering", "type": "regular", "dependencies": []},
        {"name": "D2RenderingTests", "type": "test", "dependencies": [{"byName": ["D2Rendering", None]}]},
        {"name": "ExportDiagramIntegrationTests", "type": "test", "dependencies": [{"byName": ["D2Rendering", None]}]},
    ]}

    def test_d2_source_selects_dependent_tests_and_app_integrations(self):
        mode, selected, app_mode, app = SELECTOR.select(
            ["MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/render.js"], self.manifest
        )
        self.assertEqual(mode, "selected")
        self.assertEqual(selected, "D2RenderingTests|ExportDiagramIntegrationTests")
        self.assertEqual(app_mode, "selected")
        self.assertIn("D2PreviewIntegrationTests", app)
        self.assertIn("MermaidExportRegistryTests", app)

    def test_package_test_only_change_does_not_run_app_tests(self):
        mode, selected, app_mode, app = SELECTOR.select(
            ["MacDown2/Packages/MacDownKit/Tests/D2RenderingTests/D2WebRendererTests.swift"], self.manifest
        )
        self.assertEqual((mode, selected, app_mode, app), ("selected", "D2RenderingTests", "none", ()))

    def test_unknown_or_shared_input_falls_back_to_full(self):
        for path in (
            "MacDown2/Packages/MacDownKit/Package.swift",
            "MacDown2/Packages/MacDownKit/Sources/NewTarget/Feature.swift",
            "MacDown2/MacDown2Tests/EditorTests.swift",
            ".github/workflows/ci.yml",
        ):
            with self.subTest(path=path):
                self.assertEqual(SELECTOR.select([path], self.manifest)[0], "full")

    def test_package_documentation_runs_no_product_tests(self):
        self.assertEqual(SELECTOR.select(["MacDown2/Packages/MacDownKit/README.md"], self.manifest)[0], "none")

    def test_product_change_with_planning_note_keeps_target_selection(self):
        mode, selected, app_mode, _ = SELECTOR.select([
            "MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/render.js",
            "planning/downstream/issue7-d2-layout-failure-2026-11-18.md",
        ], self.manifest)
        self.assertEqual((mode, selected, app_mode),
                         ("selected", "D2RenderingTests|ExportDiagramIntegrationTests", "selected"))


if __name__ == "__main__":
    unittest.main()
