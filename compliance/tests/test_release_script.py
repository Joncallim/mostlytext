"""Behavioural tests for release/macos/sign-notarize-dmg.sh.

The script only does real work on a Mac, but its control flow (which mode
tolerates which failure) can be tested anywhere bash runs. Each test copies
the script into a throwaway git repository, puts stub versions of the Apple
tools and of compliance.py on PATH, and runs it.

The invariant under test: --dry-run records an incomplete release gate as
UNVERIFIED and continues; --release-candidate stops on the same condition,
and stops on a failing licence gate before anything is sent to Apple.

Run: python3 -m unittest discover -s compliance/tests
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "release/macos/sign-notarize-dmg.sh"
PIN_SCRIPT = REPO / "MacDown2/scripts/pin-xcode-package-versions.sh"

STUBS = {
    "security": 'echo \'  1) ABCDEF "Developer ID Application: Test Owner (TEAMID1234)"\'',
    "sw_vers": 'echo 26.0',
    "xcodegen": "mkdir -p MacDown2.xcodeproj",
    "spctl": "true",
    "syspolicy_check": 'echo "syspolicy_check $*" >> "$CALLS"; exit "${SYSPOLICY_STATUS:-0}"',
    "shasum": textwrap.dedent("""\
        shift 2
        for f in "$@"; do
          if grep -q 'rewritten by xcodebuild' "$f"; then digest=1111
          elif grep -q 'altered before release' "$f"; then digest=2222
          else digest=0000
          fi
          echo "$digest  $f"
        done"""),
    "defaults": 'case "$3" in CFBundleShortVersionString) echo 0.1.0;; CFBundleVersion) echo 7;; *) echo com.example.App;; esac',
    "codesign": 'case "$*" in *-d*) printf "Authority=Developer ID Application: Test Owner (TEAMID1234)\\nTimestamp=now\\nflags=0x10000(runtime)\\n" >&2;; esac; true',
    "hdiutil": 'for last in "$@"; do :; done; touch "$last"',
    "ditto": 'if [ "$1" = -c ]; then for last in "$@"; do :; done; touch "$last"; else cp -R "$1" "$2"; fi',
    "xcodebuild": textwrap.dedent("""\
        if [ "$1" = -version ]; then echo "Xcode 26.0"; exit 0; fi
        echo "xcodebuild $*" >> "$CALLS"
        while [ $# -gt 0 ]; do
          case "$1" in
            -derivedDataPath) dd="$2"; shift;;
            -project) project="$2"; shift;;
            -scheme) scheme="$2"; shift;;
          esac
          shift
        done
        if [ "${XCODE_REWRITES_LOCK:-0}" = 1 ]; then
          workspace="$(dirname "$project")/MacDown2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
          mkdir -p "$workspace"
          printf 'rewritten by xcodebuild\\n' > "$workspace/Package.resolved"
        fi
        if [ "${XCODE_REWRITES_SOURCE_AND_WORKSPACE_LOCK:-0}" = 1 ]; then
          source="$(dirname "$project")/Packages/MacDownKit/Package.resolved"
          workspace="$(dirname "$project")/MacDown2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
          printf 'rewritten by xcodebuild\\n' > "$source"
          mkdir -p "$workspace"
          cp "$source" "$workspace/Package.resolved"
        fi
        out="$dd/Build/Products/Release"; mkdir -p "$out"
        if [ "$scheme" = MacDown2 ]; then mkdir -p "$out/MacDown2.app/Contents"; touch "$out/MacDown2.app/Contents/Info"
        elif [ "$scheme" = MacDown2CLI ]; then touch "$out/macdown2"
        else echo "Unknown build scheme: $scheme" >&2; exit 65; fi"""),
    "xcrun": textwrap.dedent("""\
        echo "xcrun $*" >> "$CALLS"
        case "$1 $2" in
          "notarytool submit") printf '{"id": "sub-1", "status": "%s"}\\n' "${NOTARY_STATUS:-Accepted}";;
          "notarytool log") [ "${NOTARY_LOG_FAILS:-0}" = 1 ] && exit 1; for last in "$@"; do :; done; echo '{}' > "$last";;
        esac
        true"""),
}

FAKE_COMPLIANCE = textwrap.dedent("""\
    import os, sys
    if os.environ.get("COMPLIANCE_FAILS") == "1":
        print("FAIL: example release-gate failure")
        sys.exit(1)
    print("compliance check (release): passed")
    """)


class ReleaseScriptModeTests(unittest.TestCase):
    def setUp(self) -> None:
        if shutil.which("bash") is None or shutil.which("git") is None:
            self.skipTest("needs bash and git")
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.repo = base / "repo"
        (self.repo / "release/macos").mkdir(parents=True)
        (self.repo / "compliance/tools").mkdir(parents=True)
        (self.repo / "MacDown2").mkdir()
        shutil.copy(SCRIPT, self.repo / "release/macos/sign-notarize-dmg.sh")
        (self.repo / "compliance/tools/compliance.py").write_text(FAKE_COMPLIANCE)
        package_dir = self.repo / "MacDown2/Packages/MacDownKit"
        package_dir.mkdir(parents=True)
        (package_dir / "Package.resolved").write_text('{"pins": []}\n')
        pin_script = self.repo / "MacDown2/scripts/pin-xcode-package-versions.sh"
        pin_script.parent.mkdir()
        shutil.copy(PIN_SCRIPT, pin_script)
        pin_script.chmod(0o755)
        (self.repo / ".gitignore").write_text("build/\nMacDown2/MacDown2.xcodeproj/\n")
        bin_dir = base / "bin"
        bin_dir.mkdir()
        for name, body in STUBS.items():
            stub = bin_dir / name
            stub.write_text("#!/usr/bin/env bash\n" + body + "\n")
            stub.chmod(0o755)
        self.calls = base / "calls.log"
        self.calls.touch()
        git = ["git", "-C", str(self.repo)]
        subprocess.run([*git, "init", "-q"], check=True)
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "-c", "user.name=t", "-c", "user.email=t@e", "commit", "-qm", "init"], check=True)
        self.env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}", "CALLS": str(self.calls),
                    "TEAM_ID": "TEAMID1234", "NOTARY_PROFILE": "profile", "OUT": str(base / "out")}
        self.out = base / "out"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_script(self, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(self.repo / "release/macos/sign-notarize-dmg.sh"), *args],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=60)

    def summary(self) -> str:
        return (self.out / "evidence/summary.txt").read_text()

    def test_mode_is_required(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_preflight_builds_signs_and_submits_nothing(self) -> None:
        result = self.run_script("--preflight-only")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.out / "DerivedData").exists())
        self.assertNotIn("notarytool submit", self.calls.read_text())

    def test_release_builds_use_and_preserve_the_committed_xcode_package_lock(self) -> None:
        result = self.run_script("--release-candidate")
        self.assertEqual(result.returncode, 0, result.stdout)
        source = self.repo / "MacDown2/Packages/MacDownKit/Package.resolved"
        workspace = (self.repo / "MacDown2/MacDown2.xcodeproj/project.xcworkspace/"
                     "xcshareddata/swiftpm/Package.resolved")
        self.assertEqual(workspace.read_text(), source.read_text())
        builds = [line for line in self.calls.read_text().splitlines() if line.startswith("xcodebuild ")]
        self.assertEqual(len(builds), 2)
        schemes = [build.split("-scheme ", 1)[1].split()[0] for build in builds]
        self.assertEqual(set(schemes), {"MacDown2", "MacDown2CLI"})
        self.assertEqual(len({scheme.casefold() for scheme in schemes}), 2)
        self.assertTrue(all("-onlyUsePackageVersionsFromResolvedFile" in build for build in builds))

    def test_release_build_stops_before_notarisation_when_xcode_rewrites_the_lock(self) -> None:
        result = self.run_script("--release-candidate", XCODE_REWRITES_LOCK="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Package.resolved changed during the Release builds", result.stdout)
        self.assertNotIn("notarytool submit", self.calls.read_text())

    def test_release_build_stops_when_xcode_rewrites_source_and_workspace_locks(self) -> None:
        result = self.run_script("--release-candidate", XCODE_REWRITES_SOURCE_AND_WORKSPACE_LOCK="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source Package.resolved changed during the Release builds", result.stdout)
        self.assertNotIn("notarytool submit", self.calls.read_text())

    def test_altered_initial_source_lock_is_unverified_for_dry_run_and_fatal_for_release_candidate(self) -> None:
        source = self.repo / "MacDown2/Packages/MacDownKit/Package.resolved"
        source.write_text("altered before release\n")
        dry_run = self.run_script("--dry-run")
        self.assertEqual(dry_run.returncode, 0, dry_run.stdout)
        self.assertIn("UNVERIFIED (dry run): the source Package.resolved differs", self.summary())
        self.assertEqual(
            (self.repo / "MacDown2/MacDown2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text(),
            source.read_text(),
        )
        shutil.rmtree(self.out, ignore_errors=True)
        shutil.rmtree(self.repo / "MacDown2/MacDown2.xcodeproj", ignore_errors=True)
        release_candidate = self.run_script("--release-candidate")
        self.assertNotEqual(release_candidate.returncode, 0)
        self.assertIn("source Package.resolved differs from the committed lock", release_candidate.stdout)
        self.assertFalse((self.repo / "MacDown2/MacDown2.xcodeproj").exists())

    def test_release_build_stops_before_xcodegen_when_committed_lock_is_missing(self) -> None:
        (self.repo / "MacDown2/Packages/MacDownKit/Package.resolved").unlink()
        result = self.run_script("--dry-run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("committed MacDownKit Package.resolved lock file is missing", result.stdout)
        self.assertFalse((self.repo / "MacDown2/MacDown2.xcodeproj").exists())

    def test_dry_run_records_failed_licence_gate_and_log_as_unverified_and_continues(self) -> None:
        result = self.run_script("--dry-run", COMPLIANCE_FAILS="1", NOTARY_LOG_FAILS="1")
        self.assertEqual(result.returncode, 0, result.stdout)
        summary = self.summary()
        self.assertIn("UNVERIFIED (dry run): licence gate", summary)
        self.assertIn("notarisation log app: NOT captured", summary)
        self.assertIn("UNVERIFIED (dry run): the notarisation log for app", summary)
        self.assertTrue((self.out / "MacDown2-0.1.0-7-dryrun.dmg").exists())

    def test_release_candidate_stops_on_licence_gate_before_contacting_apple(self) -> None:
        result = self.run_script("--release-candidate", COMPLIANCE_FAILS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("STOP: licence gate", result.stdout)
        self.assertNotIn("notarytool submit", self.calls.read_text())

    def test_release_candidate_stops_when_notarisation_log_is_missing(self) -> None:
        result = self.run_script("--release-candidate", NOTARY_LOG_FAILS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("STOP: the notarisation log for app", result.stdout)

    def test_rejected_notarisation_stops_every_mode_and_keeps_the_log(self) -> None:
        for mode in ("--dry-run", "--release-candidate"):
            with self.subTest(mode=mode):
                shutil.rmtree(self.out, ignore_errors=True)
                result = self.run_script(mode, NOTARY_STATUS="Invalid")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("returned 'Invalid'", result.stdout)
                self.assertTrue((self.out / "evidence/notary-app-log.json").exists())

    def test_release_candidate_requires_a_clean_tree(self) -> None:
        (self.repo / "untracked.txt").write_text("dirty\n")
        result = self.run_script("--release-candidate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clean working tree", result.stdout)

    def test_release_candidate_passes_when_every_gate_passes(self) -> None:
        result = self.run_script("--release-candidate")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("licence gate: passed", self.summary())
        self.assertNotIn("UNVERIFIED", self.summary())
        self.assertTrue((self.out / "MacDown2-0.1.0-7.dmg").exists())
        sums = (self.out / "evidence/SHA256SUMS").read_text()
        self.assertIn("macdown2.zip", sums.split("# not distributed")[0])
        self.assertIn("syspolicy_check distribution ", self.calls.read_text())

    def test_distribution_check_failure_stops_before_final_hashes(self) -> None:
        for mode in ("--dry-run", "--release-candidate"):
            with self.subTest(mode=mode):
                shutil.rmtree(self.out, ignore_errors=True)
                result = self.run_script(mode, SYSPOLICY_STATUS="70")
                self.assertEqual(result.returncode, 70, result.stdout + result.stderr)
                self.assertIn("syspolicy_check distribution ", self.calls.read_text())
                self.assertFalse((self.out / "evidence/SHA256SUMS").exists())
                self.assertNotIn("Done (", result.stdout)


if __name__ == "__main__":
    unittest.main()
