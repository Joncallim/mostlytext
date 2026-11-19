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
        {"name": "GraphvizRendering", "type": "regular", "dependencies": []},
        {"name": "GraphvizRenderingTests", "type": "test", "dependencies": [{"byName": ["GraphvizRendering", None]}]},
        {"name": "DiagramRendering", "type": "regular", "dependencies": []},
        {"name": "DiagramRenderingTests", "type": "test", "dependencies": [{"byName": ["DiagramRendering", None]}]},
        {"name": "TextSearch", "type": "regular", "dependencies": []},
        {"name": "TextSearchTests", "type": "test", "dependencies": [{"byName": ["TextSearch", None]}]},
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

    def test_graphviz_and_mermaid_use_reviewed_app_suites(self):
        for target, expected in (
            ("GraphvizRendering", "GraphvizPreviewIntegrationTests"),
            ("DiagramRendering", "MermaidPreviewIntegrationTests"),
        ):
            with self.subTest(target=target):
                mode, selected, app_mode, app = SELECTOR.select(
                    [f"MacDown2/Packages/MacDownKit/Sources/{target}/Renderer.swift"], self.manifest
                )
                self.assertEqual((mode, app_mode), ("selected", "selected"))
                self.assertIn(target + "Tests", selected)
                self.assertIn(expected, app)

    def test_combined_renderer_changes_union_app_suites(self):
        mode, selected, app_mode, app = SELECTOR.select([
            "MacDown2/Packages/MacDownKit/Sources/GraphvizRendering/GraphvizWebRenderer.swift",
            "MacDown2/Packages/MacDownKit/Sources/DiagramRendering/MermaidWebRenderer.swift",
        ], self.manifest)
        self.assertEqual((mode, app_mode), ("selected", "selected"))
        self.assertIn("GraphvizRenderingTests", selected)
        self.assertIn("DiagramRenderingTests", selected)
        self.assertIn("GraphvizPreviewIntegrationTests", app)
        self.assertIn("MermaidPreviewIntegrationTests", app)

    def test_text_search_and_its_independently_checked_ledgers_select_related_suites(self):
        paths = [
            "MacDown2/Packages/MacDownKit/Sources/TextSearch/WorkspaceReplaceEngine.swift",
            "MacDown2/Packages/MacDownKit/Sources/TextSearch/Resources/Localizable.xcstrings",
            "MacDown2/Packages/MacDownKit/Tests/TextSearchTests/WorkspaceReplaceSafetyTests.swift",
            "planning/downstream/mostlytext-localization-inventory.json",
            "planning/downstream/plain-string-sink-ledger-2026-11-09.json",
        ]
        mode, selected, app_mode, app = SELECTOR.select(paths, self.manifest)
        self.assertEqual((mode, selected, app_mode), ("selected", "TextSearchTests", "selected"))
        self.assertEqual(set(app), {
            "DocumentEditorFindNavigationTests",
            "FolderReplaceModelTests",
            "FolderSearchCancellationTests",
            "FolderSearchCountCopyTests",
            "FolderSearchModelTests",
            "FolderSearchNavigationTests",
            "NavigationOriginTests",
            "QuickOpenModelTests",
            "QuickOpenStaleOriginTests",
            "WorkspaceIndexFreshnessTests",
            "WorkspaceIndexRefreshBehaviorTests",
            "WorkspaceIndexRootPublicationTests",
        })
        self.assertEqual(SELECTOR.select(paths[-2:], self.manifest), ("none", "", "none", ()))

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

    def test_missing_or_empty_diff_runs_full_suites(self):
        self.assertEqual(SELECTOR.select([], self.manifest), ("full", "", "full", ()))

    def test_product_change_with_planning_note_keeps_target_selection(self):
        mode, selected, app_mode, _ = SELECTOR.select([
            "MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/render.js",
            "planning/downstream/issue7-d2-layout-failure-2026-11-18.md",
        ], self.manifest)
        self.assertEqual((mode, selected, app_mode),
                         ("selected", "D2RenderingTests|ExportDiagramIntegrationTests", "selected"))

    def test_release_sampler_uses_its_own_workflow(self):
        sampler = ".github/scripts/sample-diagram-budget-memory.py"
        self.assertEqual(SELECTOR.select([sampler], self.manifest)[0], "none")
        self.assertEqual(SELECTOR.select([".github/scripts/select-ci-tests.py"], self.manifest)[0], "none")
        mode, selected, app_mode, _ = SELECTOR.select([
            sampler, "MacDown2/Packages/MacDownKit/Sources/GraphvizRendering/GraphvizWebRenderer.swift",
        ], self.manifest)
        self.assertEqual((mode, selected, app_mode), ("selected", "GraphvizRenderingTests", "selected"))


if __name__ == "__main__":
    unittest.main()
