"""Tests for compliance/tools/compliance.py.

Each negative case starts from a small passing fixture tree, breaks exactly
one thing, and asserts that the check fails with the intended message. The
last test runs the real repository check so the committed inventory and
generated files cannot drift.

Run: python3 -m unittest discover -s compliance/tests
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
import tempfile
import unittest
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "compliance" / "tools"))

import compliance  # noqa: E402

LIB_JS = "MacDown2/Packages/MacDownKit/Sources/Widget/Resources/lib.js"
LIB_LICENCE = "MacDown2/Packages/MacDownKit/Sources/Widget/Resources/LIB-LICENSE.txt"
REMOTE_URL = "https://github.com/example/remote-kit"
REMOTE_REV = "1111111111111111111111111111111111111111"
FONT_BYTES = "OTTO pretend font bytes\n"
VENDORED = "MacDown2/Packages/Vendored"
QUERY = f"{VENDORED}/Sources/VendoredResources/queries/highlights.scm"
QUERY_BYTES = "(atx_heading) @markup.heading\n"


def sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


class Fixture:
    """A minimal repository that passes `check`."""

    def __init__(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.write("LICENSE", "MIT first-party licence\n")
        self.write(LIB_JS, "window.lib = 1;\n")
        self.write(LIB_LICENCE, "Example library licence\n")
        self.write("compliance/licenses/remote-kit--LICENSE.txt", "Remote kit licence\n")
        self.write("MacDown2/Packages/MacDownKit/Sources/Widget/Widget.swift", "struct Widget {}\n")
        self.write(f"{VENDORED}/Package.swift", "// swift-tools-version: 6.2\n")
        self.write(f"{VENDORED}/LICENSE", "Vendored grammar licence\n")
        self.write(f"{VENDORED}/Sources/Vendored/src/parser.c", "int parse;\n")
        self.write(QUERY, QUERY_BYTES)
        self.write(
            "MacDown2/Packages/MacDownKit/Package.swift",
            f'dependencies: [\n    .package(url: "{REMOTE_URL}", exact: "1.0.0"),\n]\n',
        )
        self.inventory = {
            "schema": 1,
            "product": {"name": "Example", "version": "1.0.0"},
            "first_party": {"licence": "MIT", "licence_text": "LICENSE", "paths": ["MacDown2/**/*.swift"]},
            "not_distributed": ["MacDown2/**/Package.swift", "MacDown2/**/Package.resolved", "MacDown2/project.yml"],
            "manifests": ["MacDown2/Packages/MacDownKit/Package.swift"],
            "lockfiles": ["MacDown2/Packages/MacDownKit/Package.resolved"],
            "build_only_packages": [],
            "lockfile_enforced": True,
            "artifact": {
                "required_first_party": ["LICENSE", compliance.NOTICES],
                "registered_extensions": [".js", ".otf", ".wasm", ".scm"],
            },
            "components": [
                {
                    "id": "lib",
                    "name": "Example lib",
                    "kind": "vendored-bundle",
                    "version": "2.0.0",
                    "upstream": "https://github.com/example/lib",
                    "revision": "2222222222222222222222222222222222222222",
                    "resolution": "exact",
                    "licence": "MPL-2.0",
                    "copyright": ["Copyright Example"],
                    "licence_texts": [{"path": LIB_LICENCE, "sha256": sha("Example library licence\n")}],
                    "owns": [LIB_JS, LIB_LICENCE],
                    "files": [{"path": LIB_JS, "sha256": sha("window.lib = 1;\n")}],
                    "runtime_resources": [{"name": "lib.js", "sha256": sha("window.lib = 1;\n"), "path": LIB_JS}],
                    "source_offer": {"required": True, "reason": "MPL-2.0", "location": "https://example.org/src/", "status": "verified"},
                    "provenance": "verified",
                },
                {
                    "id": "vendored-grammar",
                    "name": "Vendored grammar",
                    "kind": "vendored-source",
                    "version": "1.0.0",
                    "upstream": "https://github.com/example/grammar",
                    "revision": "5555555555555555555555555555555555555555",
                    "resolution": "exact",
                    "licence": "MIT",
                    "copyright": ["Copyright Grammar"],
                    "licence_texts": [{"path": f"{VENDORED}/LICENSE", "sha256": sha("Vendored grammar licence\n")}],
                    "owns": [f"{VENDORED}/**"],
                    "files": [{"path": f"{VENDORED}/Sources/Vendored/src/parser.c", "sha256": sha("int parse;\n")},
                              {"path": QUERY, "sha256": sha(QUERY_BYTES)}],
                    "runtime_resources": [{"name": "highlights.scm", "sha256": sha(QUERY_BYTES), "path": QUERY}],
                    "provenance": "verified",
                },
                {
                    "id": "remote-kit",
                    "name": "Remote kit",
                    "kind": "swiftpm",
                    "version": "1.0.0",
                    "upstream": REMOTE_URL,
                    "revision": REMOTE_REV,
                    "resolution": "exact",
                    "manifest_requirement": {"exact": "1.0.0"},
                    "licence": "MIT",
                    "copyright": ["Copyright Remote"],
                    "licence_texts": [{"path": "compliance/licenses/remote-kit--LICENSE.txt", "sha256": sha("Remote kit licence\n")}],
                    "runtime_resources": [{"name": "Remote-Font.otf", "sha256": sha(FONT_BYTES), "source": "remote-kit 1.0.0"}],
                    "provenance": "verified",
                },
            ],
        }
        self.lock(REMOTE_REV)
        self.save()

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def lock(self, revision: str) -> None:
        pins = {"pins": [{"identity": "remote-kit", "location": REMOTE_URL + ".git", "state": {"revision": revision, "version": "1.0.0"}}], "version": 3}
        self.write("MacDown2/Packages/MacDownKit/Package.resolved", json.dumps(pins))

    def save(self) -> None:
        """Write the inventory and regenerate outputs so only the mutation under test differs."""
        self.write("compliance/inventory.json", json.dumps(self.inventory, indent=2))
        compliance.main(["--root", str(self.root), "notices"])
        compliance.main(["--root", str(self.root), "sbom"])

    def make_app(self, *, skip: set[str] = frozenset(), extra: dict[str, str] | None = None) -> Path:
        """A pretend built .app holding what the fixture's contract says ships."""
        app = self.root / "build/Example.app"
        shutil.rmtree(app, ignore_errors=True)
        resources = app / "Contents/Resources"
        (resources / "Remote_Kit.bundle").mkdir(parents=True)
        (resources / "Vendored_Resources.bundle/queries").mkdir(parents=True)
        files = {
            "lib.js": (self.root / LIB_JS).read_text(),
            "Remote_Kit.bundle/Remote-Font.otf": FONT_BYTES,
            "Vendored_Resources.bundle/queries/highlights.scm": QUERY_BYTES,
            "LICENSE": (self.root / "LICENSE").read_text(),
            "THIRD_PARTY_NOTICES.md": (self.root / compliance.NOTICES).read_text(),
            **(extra or {}),
        }
        for name, body in files.items():
            if name not in skip:
                (resources / name).write_text(body, encoding="utf-8")
        return app

    def check(self, **kwargs) -> compliance.Report:
        return compliance.check(self.root, **kwargs)

    def close(self) -> None:
        self.dir.cleanup()


class ComplianceCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fx = Fixture()

    def tearDown(self) -> None:
        self.fx.close()

    def assertFailsWith(self, fragment: str, **kwargs) -> None:
        report = self.fx.check(**kwargs)
        self.assertTrue(any(fragment in e for e in report.errors), f"expected an error containing {fragment!r}, got {report.errors}")

    def test_baseline_fixture_passes_tree_and_release_checks(self) -> None:
        self.assertEqual(self.fx.check().errors, [])
        self.assertEqual(self.fx.check(release=True).errors, [])

    def test_unregistered_component_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Sources/Widget/Resources/extra.min.js", "window.extra = 1;\n")
        self.assertFailsWith("unregistered distributed file")

    def test_unregistered_swiftpm_dependency_fails(self) -> None:
        self.fx.write(
            "MacDown2/Packages/MacDownKit/Package.swift",
            f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(url: "https://github.com/example/new", from: "1.0.0"),\n',
        )
        self.assertFailsWith("is not registered in the inventory")

    def test_unregistered_resolved_package_fails(self) -> None:
        pins = {"pins": [
            {"location": REMOTE_URL, "state": {"revision": REMOTE_REV}},
            {"location": "https://github.com/example/transitive", "state": {"revision": "3" * 40}},
        ]}
        self.fx.write("MacDown2/Packages/MacDownKit/Package.resolved", json.dumps(pins))
        self.assertFailsWith("resolved package https://github.com/example/transitive is not registered")

    def test_deleted_notice_fails(self) -> None:
        (self.fx.root / LIB_LICENCE).unlink()
        self.assertFailsWith("licence/notice text missing")

    def test_edited_notice_fails(self) -> None:
        self.fx.write(LIB_LICENCE, "Truncated\n")
        self.assertFailsWith("licence/notice text changed")

    def test_wrong_digest_fails(self) -> None:
        self.fx.write(LIB_JS, "window.lib = 2;\n")
        self.assertFailsWith("distributed file digest mismatch")

    def test_stale_lockfile_mapping_fails(self) -> None:
        self.fx.lock("4" * 40)
        self.assertFailsWith("stale mapping")

    def test_stale_manifest_mapping_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", f'.package(url: "{REMOTE_URL}", exact: "1.1.0"),\n')
        self.assertFailsWith("stale mapping")

    def test_missing_required_source_location_fails(self) -> None:
        self.fx.inventory["components"][0]["source_offer"]["location"] = ""
        self.fx.save()
        self.assertFailsWith("no source location is recorded")

    def test_unverified_source_location_fails_release_only(self) -> None:
        self.fx.inventory["components"][0]["source_offer"]["status"] = "planned"
        self.fx.save()
        self.assertEqual(self.fx.check().errors, [])
        self.assertFailsWith("not verified by anonymous retrieval", release=True)

    def test_enforced_lockfile_missing_fails_tree_check(self) -> None:
        (self.fx.root / "MacDown2/Packages/MacDownKit/Package.resolved").unlink()
        self.assertFailsWith("no Package.resolved found")

    def test_enforced_registered_package_missing_from_lockfile_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.resolved", json.dumps({"pins": [], "version": 3}))
        self.assertFailsWith("remote-kit: registered SwiftPM component is absent from the lock file")

    def test_lockfile_findings_are_unverified_until_enforced(self) -> None:
        self.fx.inventory["lockfile_enforced"] = False
        self.fx.save()
        self.fx.lock("4" * 40)
        report = self.fx.check()
        self.assertEqual(report.errors, [])
        self.assertTrue(any("stale mapping" in w for w in report.warnings))
        self.assertFailsWith("stale mapping", release=True)

    def test_missing_lockfile_is_unverified_in_tree_mode_and_fails_release(self) -> None:
        self.fx.inventory["lockfile_enforced"] = False
        self.fx.save()
        (self.fx.root / "MacDown2/Packages/MacDownKit/Package.resolved").unlink()
        report = self.fx.check()
        self.assertEqual(report.errors, [])
        self.assertTrue(any("no Package.resolved" in w for w in report.warnings))
        self.assertFailsWith("no Package.resolved", release=True)

    def test_pending_component_fails_release(self) -> None:
        self.fx.inventory["components"][2]["resolution"] = "pending-lockfile"
        self.fx.inventory["components"][2]["provenance"] = "pending"
        self.fx.save()
        self.assertFailsWith("revision still pending", release=True)

    def test_open_item_fails_release(self) -> None:
        self.fx.inventory["components"][2]["open_items"] = ["needs a look"]
        self.fx.save()
        self.assertFailsWith("open item: needs a look", release=True)

    def test_stale_generated_notices_fail(self) -> None:
        self.fx.inventory["components"][2]["copyright"] = ["Copyright Someone Else"]
        self.fx.write("compliance/inventory.json", json.dumps(self.fx.inventory, indent=2))
        self.assertFailsWith("generated file is stale")

    # ------------------------------------------------------------ artifact

    def test_complete_artifact_passes_release_check(self) -> None:
        self.assertEqual(self.fx.check(release=True, artifact=self.fx.make_app()).errors, [])

    def test_artifact_missing_vendored_engine_fails(self) -> None:
        self.assertFailsWith("required runtime resource lib.js", artifact=self.fx.make_app(skip={"lib.js"}))

    def test_artifact_missing_dependency_font_fails(self) -> None:
        self.assertFailsWith("required runtime resource Remote-Font.otf", artifact=self.fx.make_app(skip={"Remote_Kit.bundle/Remote-Font.otf"}))

    def test_artifact_with_modified_runtime_resource_fails(self) -> None:
        app = self.fx.make_app(extra={"lib.js": "window.lib = 'patched after build';\n"})
        self.assertFailsWith("required runtime resource lib.js", artifact=app)

    def test_artifact_without_notices_fails(self) -> None:
        self.assertFailsWith("does not contain the generated THIRD_PARTY_NOTICES.md", artifact=self.fx.make_app(skip={"THIRD_PARTY_NOTICES.md"}))

    def test_artifact_with_stale_notices_fails(self) -> None:
        app = self.fx.make_app(extra={"THIRD_PARTY_NOTICES.md": "# an older notices file\n"})
        self.assertFailsWith("does not contain the generated THIRD_PARTY_NOTICES.md", artifact=app)

    def test_artifact_without_first_party_licence_fails(self) -> None:
        self.assertFailsWith("does not contain first-party LICENSE", artifact=self.fx.make_app(skip={"LICENSE"}))

    def test_artifact_shipping_unregistered_font_or_script_fails(self) -> None:
        for name in ("Surprise.otf", "tracker.js", "engine.wasm"):
            with self.subTest(name=name):
                self.assertFailsWith(f"unregistered runtime file: Contents/Resources/{name}", artifact=self.fx.make_app(extra={name: "unknown\n"}))

    def test_artifact_may_ship_first_party_scripts(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Sources/Widget/Resources/render.js", "render();\n")
        self.fx.inventory["first_party"]["paths"].append("MacDown2/**/render.js")
        self.fx.save()
        self.assertEqual(self.fx.check(artifact=self.fx.make_app(extra={"render.js": "render();\n"})).errors, [])

    def test_stale_runtime_resource_digest_fails_in_tree_mode(self) -> None:
        self.fx.inventory["components"][0]["runtime_resources"][0]["sha256"] = "0" * 64
        self.fx.save()
        self.assertFailsWith("runtime resource digest is stale")

    def test_vendored_bundle_without_runtime_resources_fails(self) -> None:
        del self.fx.inventory["components"][0]["runtime_resources"]
        self.fx.save()
        self.assertFailsWith("must declare runtime_resources")

    # ------------------------------------------------ wildcard-owned packages

    def test_unregistered_query_inside_wildcard_owned_package_fails(self) -> None:
        """The original bypass: `owns: Vendored/**` must not make a new shipped query compliant."""
        self.fx.write(f"{VENDORED}/Sources/VendoredResources/queries/extra.scm", "(x) @y\n")
        self.assertFailsWith("vendored-grammar: file inside its owned boundary is not in its audited files")

    def test_swift_file_inside_vendored_package_cannot_pass_as_first_party(self) -> None:
        self.fx.write(f"{VENDORED}/Sources/Vendored/Helper.swift", "struct Helper {}\n")
        self.assertFailsWith("file inside its owned boundary is not in its audited files")

    def test_registered_query_inside_wildcard_owned_package_passes(self) -> None:
        self.assertEqual(self.fx.check().errors, [])
        self.assertEqual(self.fx.check(release=True, artifact=self.fx.make_app()).errors, [])

    def test_artifact_missing_registered_query_fails(self) -> None:
        self.assertFailsWith("required runtime resource highlights.scm", artifact=self.fx.make_app(skip={"Vendored_Resources.bundle/queries/highlights.scm"}))

    def test_artifact_shipping_unknown_query_fails(self) -> None:
        app = self.fx.make_app(extra={"Vendored_Resources.bundle/queries/extra.scm": "(x) @y\n"})
        self.assertFailsWith("unregistered runtime file: Contents/Resources/Vendored_Resources.bundle/queries/extra.scm", artifact=app)

    # ------------------------------------------------ project.yml requirements

    def test_xcodegen_requirement_matching_inventory_passes(self) -> None:
        self.fx.write("MacDown2/project.yml", f"packages:\n  RemoteKit:\n    url: {REMOTE_URL}\n    exactVersion: 1.0.0\n")
        self.assertEqual(self.fx.check().errors, [])

    def test_xcodegen_requirement_change_is_a_stale_mapping(self) -> None:
        for requirement in ("exactVersion: 1.1.0", "branch: main", "minorVersion: 1.0.0", "minVersion: 1.0.0"):
            with self.subTest(requirement=requirement):
                self.fx.write("MacDown2/project.yml", f"packages:\n  RemoteKit:\n    url: {REMOTE_URL}\n    {requirement}\n")
                self.assertFailsWith("stale mapping: MacDown2/project.yml requires")

    def test_xcodegen_packages_are_read_at_any_indentation(self) -> None:
        for indent in (2, 4):
            with self.subTest(indent=indent):
                pad = " " * indent
                self.fx.write("MacDown2/project.yml",
                              f"packages:\n{pad}Sneaky:\n{pad * 2}url: https://github.com/example/indented\n{pad * 2}from: 1.0.0\n")
                self.assertFailsWith("project.yml: package https://github.com/example/indented is not registered")

    def test_unreadable_xcodegen_package_entry_fails_closed(self) -> None:
        self.fx.write("MacDown2/project.yml", "packages:\n  Sneaky: {url: https://github.com/example/flow, from: 1.0.0}\n")
        self.assertFailsWith("project.yml: unrecognised package entry")

    def test_missing_artifact_fails(self) -> None:
        self.assertFailsWith("artifact not found", artifact=self.fx.root / "build/Nope.app")

    # ------------------------------------------------------------ manifests

    def test_unregistered_multiline_dependency_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", textwrap.dedent(f"""\
            dependencies: [
                .package(url: "{REMOTE_URL}", exact: "1.0.0"),
                .package(
                    url: "https://github.com/example/sneaky",
                    exact: "2.0.0"
                ),
            ]
            """))
        self.assertFailsWith("dependency https://github.com/example/sneaky is not registered")

    def test_multiline_requirement_change_is_a_stale_mapping(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(\n    url: "{REMOTE_URL}",\n    branch: "main"\n)\n')
        self.assertFailsWith("stale mapping")

    def test_range_requirement_never_matches_a_recorded_one(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", f'.package(url: "{REMOTE_URL}", "1.0.0"..<"2.0.0")\n')
        self.assertFailsWith("stale mapping")

    def test_commented_out_dependencies_are_ignored(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", textwrap.dedent(f"""\
            // .package(url: "https://github.com/example/old", exact: "1.0.0"),
            /* .package(
                url: "https://github.com/example/older", exact: "1.0.0") */
            .package(url: "{REMOTE_URL}", exact: "1.0.0"), // "https://not/a/dep"
            """))
        self.assertEqual(self.fx.check().errors, [])

    def test_unrecognised_package_declaration_fails_closed(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(id: "example.registry", from: "1.0.0"),\n')
        self.assertFailsWith("unrecognised package declaration")

    def _authored_local_package(self) -> str:
        package = "MacDown2/Packages/Authored"
        self.fx.write(package + "/Package.swift", "// swift-tools-version: 6.2\n")
        self.fx.write(package + "/Sources/Authored/Value.swift", "struct Value {}\n")
        self.fx.inventory["first_party"]["packages"] = [package]
        self.fx.inventory["manifests"].append(package + "/Package.swift")
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(path: "../Authored"),\n')
        self.fx.save()
        return package

    def test_explicit_first_party_local_package_passes_without_external_notice(self) -> None:
        self._authored_local_package()
        self.assertEqual(self.fx.check().errors, [])
        self.assertEqual(self.fx.check(release=True).errors, [])
        self.assertNotIn("Authored", compliance.render_notices(self.fx.root, self.fx.inventory))

    def test_first_party_package_declaration_rejects_invalid_types(self) -> None:
        self._authored_local_package()
        for value in ["MacDown2/Packages/Authored", [None], [123]]:
            with self.subTest(value=value):
                self.fx.inventory["first_party"]["packages"] = value
                self.fx.save()
                self.assertFailsWith("first_party.packages must be a list of strings")

    def test_first_party_package_duplicate_declaration_fails(self) -> None:
        package = self._authored_local_package()
        self.fx.inventory["first_party"]["packages"] = [package, package]
        self.fx.save()
        self.assertFailsWith("duplicate first-party package declaration")

    def test_first_party_package_path_escape_and_alias_fail(self) -> None:
        self._authored_local_package()
        for path in ["../outside", "/tmp", "MacDown2/Packages/../Packages/Authored"]:
            with self.subTest(path=path):
                self.fx.inventory["first_party"]["packages"] = [path]
                self.fx.save()
                self.assertFailsWith("first-party package path must be canonical inside MacDown2/")

    def test_first_party_package_symlink_cannot_escape_the_checked_tree(self) -> None:
        package = self._authored_local_package()
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside)
            (external / "Package.swift").write_text('.package(id: "external.registry", from: "1.0.0")\n')
            target = self.fx.root / package
            shutil.rmtree(target)
            target.symlink_to(external, target_is_directory=True)
            self.assertFailsWith("first-party package path must be canonical inside MacDown2/")
            self.assertFalse(any("unrecognised package declaration" in error for error in self.fx.check().errors))

    def test_first_party_package_source_symlink_cannot_borrow_first_party_globs(self) -> None:
        package = self._authored_local_package()
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / "Foreign.swift"
            external.write_text("struct Foreign {}\n")
            (self.fx.root / package / "Sources/Authored/Foreign.swift").symlink_to(external)
            self.assertFailsWith("first-party package contains symlinked content")

    def test_first_party_package_nested_directory_symlink_is_not_an_owner(self) -> None:
        package = self._authored_local_package()
        with tempfile.TemporaryDirectory() as outside:
            (Path(outside) / "Foreign.swift").write_text("struct Foreign {}\n")
            (self.fx.root / package / "Sources/Foreign").symlink_to(outside, target_is_directory=True)
            self.assertFailsWith("first-party package contains symlinked content")

    def test_first_party_package_manifest_symlink_is_rejected_without_parsing_it(self) -> None:
        package = self._authored_local_package()
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / "Package.swift"
            external.write_text('.package(id: "external.registry", from: "1.0.0")\n')
            manifest = self.fx.root / package / "Package.swift"
            manifest.unlink()
            manifest.symlink_to(external)
            errors = self.fx.check().errors
            self.assertTrue(any("manifest must not be a symlink" in error for error in errors), errors)
            self.assertFalse(any("unrecognised package declaration" in error for error in errors), errors)

    def test_first_party_package_requires_existing_manifest(self) -> None:
        package = self._authored_local_package()
        (self.fx.root / package / "Package.swift").unlink()
        self.assertFailsWith("first-party package manifest is missing")

    def test_first_party_package_requires_explicit_manifest_registration(self) -> None:
        package = self._authored_local_package()
        self.fx.inventory["manifests"].remove(package + "/Package.swift")
        self.fx.save()
        self.assertFailsWith("first-party package manifest must be explicitly registered")

    def test_third_party_package_cannot_be_reclassified_as_first_party(self) -> None:
        self.fx.inventory["first_party"]["packages"] = [VENDORED]
        self.fx.inventory["manifests"].append(VENDORED + "/Package.swift")
        self.fx.save()
        self.assertFailsWith("first-party package conflicts with a third-party package owner")

    def test_first_party_package_still_checks_unknown_remote_dependencies(self) -> None:
        package = self._authored_local_package()
        self.fx.write(package + "/Package.swift", '.package(url: "https://github.com/example/not-approved", exact: "1.0.0")\n')
        self.assertFailsWith("dependency https://github.com/example/not-approved is not registered")

    def test_first_party_package_does_not_own_a_nested_local_package(self) -> None:
        package = self._authored_local_package()
        self.fx.write(package + "/Package.swift", '.package(path: "Nested")\n')
        self.fx.write(package + "/Nested/Package.swift", "// nested\n")
        self.assertFailsWith("local package MacDown2/Packages/Authored/Nested is not owned")

    def test_first_party_package_does_not_exempt_unregistered_c_source(self) -> None:
        package = self._authored_local_package()
        self.fx.write(package + "/Sources/Authored/vendor.c", "int foreign;\n")
        self.assertFailsWith("unregistered distributed file")

    def test_unowned_multiline_local_package_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(\n    path: "../Sneaky"\n),\n')
        self.assertFailsWith("local package MacDown2/Packages/Sneaky is not owned")

    def test_new_local_package_manifest_is_checked_automatically(self) -> None:
        self.fx.write("MacDown2/Packages/Helper/Package.swift", '.package(url: "https://github.com/example/transitive-sneak", from: "1.0.0")\n')
        self.assertFailsWith("MacDown2/Packages/Helper/Package.swift: dependency https://github.com/example/transitive-sneak is not registered")

    def test_unregistered_xcodegen_package_fails(self) -> None:
        self.fx.write("MacDown2/project.yml", textwrap.dedent("""\
            name: Example
            packages:
              Sneaky:
                url: https://github.com/example/xcodegen-sneak
                from: 1.0.0
            targets: {}
            """))
        self.assertFailsWith("project.yml: package https://github.com/example/xcodegen-sneak is not registered")

    def test_xcodegen_package_outside_the_checked_tree_fails(self) -> None:
        self.fx.write("MacDown2/project.yml", "packages:\n  Outside:\n    path: ../../elsewhere\n")
        self.assertFailsWith("outside MacDown2/")

    def test_unregistered_file_in_existing_target_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Sources/Widget/vendor.c", "int x;\n")
        self.assertFailsWith("unregistered distributed file")

    def test_generation_is_deterministic(self) -> None:
        inventory = compliance.load_inventory(self.fx.root)
        self.assertEqual(compliance.render_notices(self.fx.root, inventory), compliance.render_notices(self.fx.root, inventory))
        self.assertEqual(compliance.render_sbom(self.fx.root, inventory), compliance.render_sbom(self.fx.root, inventory))


class ManifestParserTests(unittest.TestCase):
    def test_single_and_multiline_forms_agree(self) -> None:
        single = '.package(url: "https://github.com/a/b", exact: "1.0.0")\n.package(path: "../X")\n'
        multi = '.package(\n    url: "https://github.com/a/b",\n    exact: "1.0.0"\n)\n.package(\n  path: "../X"\n)\n'
        self.assertEqual(compliance.parse_manifest(single), compliance.parse_manifest(multi))
        self.assertEqual(compliance.parse_manifest(single), ([("https://github.com/a/b", {"exact": "1.0.0"})], ["../X"], []))

    def test_requirement_keywords(self) -> None:
        for requirement, expected in (('exact: "1.0.0"', {"exact": "1.0.0"}), ('from: "1.0.0"', {"from": "1.0.0"}),
                                      ('branch: "main"', {"branch": "main"}), ('revision: "abc"', {"revision": "abc"}),
                                      ('.upToNextMinor(from: "0.25.0")', {"from": "0.25.0", "form": "upToNextMinor"})):
            with self.subTest(requirement=requirement):
                urls, _, _ = compliance.parse_manifest(f'.package(url: "https://github.com/a/b", {requirement})')
                self.assertEqual(urls[0][1], expected)


class RepositoryTests(unittest.TestCase):
    def test_committed_inventory_passes_tree_check(self) -> None:
        report = compliance.check(REPO)
        self.assertEqual(report.errors, [], "\n".join(report.errors))

    def test_generated_app_metadata_does_not_hide_unregistered_plists(self) -> None:
        """XcodeGen's app metadata ships; other plist files still need ownership."""
        fixture = Fixture()
        self.addCleanup(fixture.close)
        fixture.inventory["first_party"]["paths"] = compliance.load_inventory(REPO)["first_party"]["paths"]
        fixture.save()
        fixture.write("MacDown2/MacDown2/Info.plist", "<plist><dict/></plist>\n")
        self.assertEqual(fixture.check().errors, [])

        unexpected = "MacDown2/MacDown2/Unregistered.plist"
        fixture.write(unexpected, "<plist><dict/></plist>\n")
        errors = fixture.check().errors
        self.assertEqual(len(errors), 1)
        self.assertIn("unregistered distributed file", errors[0])
        self.assertIn(unexpected, errors[0])

    def test_every_manifest_dependency_is_parsed(self) -> None:
        """Checks the parser against oracles that don't share its logic.

        1. Every quoted http(s) URL outside a // comment line is a dependency.
        2. The number of `.package(` tokens outside // comment lines equals
           the number of parsed declarations, and none is unrecognised.
        3. Reflowing every declaration onto multiple lines changes nothing.
        """
        for manifest in sorted(REPO.glob("MacDown2/Packages/*/Package.swift")):
            with self.subTest(manifest=manifest.relative_to(REPO).as_posix()):
                text = manifest.read_text(encoding="utf-8")
                code_lines = [line for line in text.splitlines() if not line.lstrip().startswith("//")]
                code = "\n".join(code_lines)
                urls, paths, unknown = compliance.parse_manifest(text)
                self.assertEqual(unknown, [])
                self.assertEqual({u for u, _ in urls}, set(re.findall(r'"(https?://[^"]+)"', code)))
                self.assertEqual(len(urls) + len(paths), len(re.findall(r"\.package\s*\(", code)))
                reflowed = re.sub(r",\s*(url|path|exact|from|branch|revision|name):", r",\n        \1:", text)
                reflowed = reflowed.replace(".package(", ".package(\n        ")
                # A Foundation-only package can have zero dependencies. Reflow
                # its container too, preserving the real-mutation oracle.
                reflowed = reflowed.replace("Package(", "Package(\n        ")
                self.assertNotEqual(reflowed, text)
                self.assertEqual(compliance.parse_manifest(reflowed), (urls, paths, unknown))

    def test_lockfile_is_enforced_and_nothing_is_pending_it(self) -> None:
        """LC-05 landed in #165; the committed lock file is now a hard part of the gate."""
        inventory = compliance.load_inventory(REPO)
        self.assertIs(inventory["lockfile_enforced"], True)
        self.assertTrue((REPO / "MacDown2/Packages/MacDownKit/Package.resolved").is_file())
        pending = [c["id"] for c in inventory["components"] if c.get("resolution") == "pending-lockfile"]
        self.assertEqual(pending, [])

    def test_compliance_workflow_cannot_be_skipped_by_path_filters(self) -> None:
        """The check walks the whole tree, so the workflow must run on every change."""
        workflow = (REPO / ".github/workflows/compliance.yml").read_text(encoding="utf-8")
        triggers = workflow.split("\njobs:", 1)[0]
        self.assertNotRegex(triggers, r"(?m)^\s*(paths|paths-ignore|branches-ignore)\s*:")
        self.assertRegex(triggers, r"(?m)^  pull_request:")
        self.assertRegex(triggers, r"(?m)^  push:")
        self.assertIn("python3 compliance/tools/compliance.py check\n", workflow)
        self.assertIn("python3 -m unittest discover -s compliance/tests", workflow)

    def test_every_vendored_bundle_and_math_font_is_in_the_artifact_contract(self) -> None:
        inventory = compliance.load_inventory(REPO)
        by_id = {c["id"]: c for c in inventory["components"]}
        for component in inventory["components"]:
            if component["kind"] == "vendored-bundle":
                self.assertTrue(component.get("runtime_resources"), component["id"])
        # Tree-sitter query files ship as resources (vendored and remote
        # grammars copy their queries/ folders), so they must stay controlled.
        self.assertIn(".scm", inventory["artifact"]["registered_extensions"])
        for component in inventory["components"]:
            if component["id"].startswith("tree-sitter-") and component["kind"] in ("swiftpm", "vendored-source"):
                self.assertTrue(any(r["name"].endswith(".scm") for r in component.get("runtime_resources", [])), component["id"])
        fonts = {r["name"] for r in by_id["swiftui-math-fonts"]["runtime_resources"]}
        self.assertEqual(len(fonts), len(by_id["swiftui-math-fonts"]["fonts"]))
        self.assertTrue(all(name.endswith(".otf") for name in fonts))


if __name__ == "__main__":
    unittest.main()
