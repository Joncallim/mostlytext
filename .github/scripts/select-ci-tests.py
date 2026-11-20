#!/usr/bin/env python3
"""Select PR or main-push suites from changed package targets; fail open to full."""

import argparse
import json
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
PACKAGE = "MacDown2/Packages/MacDownKit/"
D2_APP_SUITES = (
    "D2PreviewIntegrationTests",
    "D2ExportRegistryTests",
    "MermaidExportRegistryTests",
    "MixedDiagramRendererIntegrationTests",
    "DiagramFailurePresentationTests",
    "RenderedStateEvidenceTests",
)
GRAPHVIZ_APP_SUITES = (
    "GraphvizPreviewIntegrationTests",
    "GraphvizExportRegistryTests",
    "MermaidExportRegistryTests",
    "MixedDiagramRendererIntegrationTests",
    "DiagramFailurePresentationTests",
    "RenderedStateEvidenceTests",
)
MERMAID_APP_SUITES = (
    "MermaidPreviewIntegrationTests",
    "MermaidExportRegistryTests",
    "MixedDiagramRendererIntegrationTests",
    "DiagramFailurePresentationTests",
    "RenderedStateEvidenceTests",
)
TEXT_SEARCH_APP_SUITES = (
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
)
THEME_APP_SUITES = (
    "DocumentWindowSettingsTests",
    "RenderedStateEvidenceTests",
    "ThemeCatalogModelTests",
)
APP_SUITE_FAMILIES = (
    ({"D2Rendering", "DiagramsD2"}, D2_APP_SUITES),
    ({"GraphvizRendering", "DiagramsGraphviz"}, GRAPHVIZ_APP_SUITES),
    ({"DiagramRendering"}, MERMAID_APP_SUITES),
    ({"TextSearch"}, TEXT_SEARCH_APP_SUITES),
    ({"Themes"}, THEME_APP_SUITES),
)
INDEPENDENTLY_CHECKED_EVIDENCE = {
    "planning/downstream/mostlytext-localization-inventory.json",
    "planning/downstream/plain-string-sink-ledger-2026-11-09.json",
}
THEME_APP_INPUTS = {
    "MacDown2/MacDown2/ThemeCatalogModel+Actions.swift",
    "MacDown2/MacDown2Tests/ThemeCatalogModelTests.swift",
}
THEME_WORKFLOW_INPUTS = {
    ".github/scripts/run-current-line-theme-probe.py",
    ".github/workflows/current-line-theme-probe.yml",
}
THEME_CONTROLLER_SOURCE = "MacDown2/Packages/MacDownKit/Sources/Themes/ThemeController.swift"
THEME_CONTROLLER_SCOPE = THEME_APP_INPUTS | THEME_WORKFLOW_INPUTS | {
    THEME_CONTROLLER_SOURCE,
    ".github/scripts/select-ci-tests.py",
    ".github/scripts/test_select_ci_tests.py",
}


def target_dependencies(target):
    return {entry["byName"][0] for entry in target.get("dependencies", []) if "byName" in entry}


def select(paths, manifest):
    if not paths:
        return ("full", "", "full", ())
    changed = set()
    theme_app_input = False
    app_input = False
    tests = {target["name"] for target in manifest["targets"] if target["type"] == "test"}
    sources = {target["name"] for target in manifest["targets"] if target["type"] != "test"}
    if (THEME_CONTROLLER_SOURCE in paths and "Themes" in sources and "ThemesTests" in tests
            and all(path in THEME_CONTROLLER_SCOPE or
                    (path.startswith("planning/downstream/") and path.endswith(".md")) for path in paths)):
        # ThemeController owns selection policy in the app. Its exact scoped
        # lane runs the complete theme target and three actual app consumers;
        # any other Themes input retains dependency-graph selection below.
        return ("selected", "ThemesTests", "selected", tuple(sorted(THEME_APP_SUITES)))
    for path in paths:
        if path.startswith(PACKAGE + "Sources/") or path.startswith(PACKAGE + "Tests/"):
            parts = path[len(PACKAGE):].split("/")
            if len(parts) < 3 or parts[1] not in sources | tests:
                return ("full", "", "full", ())
            changed.add(parts[1])
        elif path.endswith(".md"):
            # Repository prose does not alter compiled targets; resource Markdown
            # under Sources/ was handled above and still selects its target.
            continue
        elif path in INDEPENDENTLY_CHECKED_EVIDENCE:
            # The compliance workflow validates both generated ledgers and
            # their tool tests; neither is compiled into the app or package.
            continue
        elif path in THEME_APP_INPUTS:
            theme_app_input = True
        elif path.startswith(("MacDown2/MacDown2/", "MacDown2/MacDown2Tests/")):
            # App-only source/tests cannot alter package tests. Keep the full
            # app suite because there is no app-target dependency graph.
            app_input = True
        elif path in THEME_WORKFLOW_INPUTS:
            # The dedicated Debug/Release theme workflow runs and verifies
            # this probe; it does not change the product test graph.
            continue
        elif path in {
            ".github/scripts/sample-diagram-budget-memory.py",
            ".github/scripts/select-ci-tests.py",
            ".github/scripts/test_select_ci_tests.py",
        }:
            # The Release sampler has its own workflow; the selector's own
            # safety tests run at the start of every CI job. None changes a
            # product target or ordinary package/app test input.
            continue
        else:
            # Manifests, lockfiles, app sources, resources outside a target,
            # workflows and selector changes can affect any suite.
            return ("full", "", "full", ())
    if not changed:
        if theme_app_input:
            return ("full", "", "full", ())
        return ("app-only", "", "full", ()) if app_input else ("none", "", "none", ())
    closure = set(changed)
    while True:
        additions = {
            target["name"]
            for target in manifest["targets"]
            if target_dependencies(target) & closure
        }
        if additions <= closure:
            break
        closure |= additions
    selected = sorted(closure & tests)
    if not selected:
        return ("full", "", "full", ())
    # App tests have no SwiftPM target graph. Use only reviewed app-suite maps;
    # other package source changes retain the full app suite.
    changed_sources = changed & sources
    if theme_app_input and changed_sources != {"Themes"}:
        return ("full", "", "full", ())
    if app_input:
        return ("selected", "|".join(re.escape(name) for name in selected), "full", ())
    if not changed_sources:
        app_mode, app = "none", ()
    elif changed_sources <= set().union(*(targets for targets, _ in APP_SUITE_FAMILIES)):
        app_mode = "selected"
        app = tuple(sorted({suite for targets, suites in APP_SUITE_FAMILIES
                            if targets & changed_sources for suite in suites}))
    else:
        app_mode, app = "full", ()
    return ("selected", "|".join(re.escape(name) for name in selected), app_mode, app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.base == "0" * 40:
        paths = []
    else:
        try:
            paths = subprocess.check_output(
                ["git", "diff", "--name-only", "-z", args.base, "HEAD", "--"],
                cwd=ROOT, stderr=subprocess.DEVNULL
            ).decode().split("\0")
            paths = [path for path in paths if path]
        except subprocess.CalledProcessError:
            paths = []
    manifest = json.loads(subprocess.check_output(
        ["swift", "package", "dump-package", "--package-path", str(ROOT / PACKAGE)], cwd=ROOT
    ))
    mode, package_filter, app_mode, app_suites = select(paths, manifest)
    lines = [f"CI_TEST_MODE={mode}", f"CI_PACKAGE_FILTER={package_filter}",
             f"CI_APP_TEST_MODE={app_mode}", f"CI_APP_SUITES={','.join(app_suites)}"]
    args.output.open("a").write("\n".join(lines) + "\n")
    print(json.dumps({"paths": paths, "mode": mode, "package_filter": package_filter,
                      "app_mode": app_mode, "app_suites": app_suites}, indent=2))


if __name__ == "__main__":
    main()
