#!/usr/bin/env python3
"""Guarded hosted A/B of the same mounted Copy test with two immutable Textual heads."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

from preview_compiled_inputs import capture, check_host, verify


OLD = "d2f8488476a26a1c22d173026bcd7b231cd75b4a"
NEW = "45d5ef2d9a2d0d993de265ffeba7697db97799f5"
REVISIONS = {"old": OLD, "new": NEW}
PACKAGE = Path("MacDown2/Packages/MacDownKit")
LOCK = PACKAGE / "Package.resolved"
MANIFEST = PACKAGE / "Package.swift"
PROJECT = Path("MacDown2/project.yml")
INVENTORY = Path("compliance/inventory.json")
CHANGED_PIN_PATHS = {str(LOCK), str(MANIFEST), str(PROJECT), str(INVENTORY)}
REPEATS = 10
TEST_URL = ("test://com.apple.xcode/MacDown2/MacDown2Tests/SecuredMarkdownMountedTests/"
            "aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration()")
# The full-function selector selected zero Swift Testing functions on the first
# hosted A/B. The unchanged original hosted workflow used this suite selector
# and executed all four functions; require their exact XCResult IDs below.
TEST = "-only-testing:MacDown2Tests/SecuredMarkdownMountedTests"
EXPECTED_TEST_URLS = frozenset(
    "test://com.apple.xcode/MacDown2/MacDown2Tests/SecuredMarkdownMountedTests/" + name + "()"
    for name in (
        "aNoWriteNativeCopyCannotReuseAnEarlierImage",
        "aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration",
        "aNewParsedRevisionReplacesTheLoadWithoutAnotherModelEdit",
        "hidingDuringAParsedFrameReplacementRevokesTheRetainedLoader",
    )
)
ROOT = Path(os.environ.get("RUNNER_TEMP", "/missing-runner-temp")) / "preview-grant-probe"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def tracked_hashes():
    names = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    return {name: digest(Path(name).read_bytes()) for name in names if name
            and (name.startswith("MacDown2/") or name in {
                str(INVENTORY), ".github/workflows/preview-grant-probe.yml",
                ".github/scripts/preview-selection-ab.py",
                ".github/scripts/test-preview-selection-ab.py",
                ".github/scripts/verify-preview-inline-selection-correlation.py",
                ".github/scripts/test-preview-inline-selection-correlation.py",
                ".github/scripts/run-owned-app-tests.py",
                ".github/scripts/preview_compiled_inputs.py",
            })}


def replace_exact(source, old, new):
    if source.count(old) != 1:
        raise ValueError("The immutable Textual revision must occur exactly once")
    return source.replace(old, new)


def validate_pins(before, after, revision):
    if before.get("version") != after.get("version") or len(before["pins"]) != 24 or len(after["pins"]) != 24:
        raise ValueError("The exact 24-pin package closure changed")
    original = {pin["identity"]: pin for pin in before["pins"]}
    candidate = {pin["identity"]: pin for pin in after["pins"]}
    if len(original) != 24 or len(candidate) != 24 or original.keys() != candidate.keys():
        raise ValueError("Package identities changed")
    for identity, pin in original.items():
        expected = json.loads(json.dumps(pin))
        if identity == "textual":
            if pin["location"] != "https://github.com/Joncallim/textual" or pin["state"] != {"revision": NEW}:
                raise ValueError("The source is not the exact private new-variant lock")
            expected["state"] = {"revision": revision}
        if candidate[identity] != expected:
            raise ValueError("Unexpected package change: " + identity)


def source_delta(before, after, variant):
    changed = {name for name in before.keys() | after.keys() if before.get(name) != after.get(name)}
    expected = CHANGED_PIN_PATHS if variant == "old" else set()
    if changed != expected:
        raise ValueError(f"Only four pin metadata files may differ: {sorted(changed)}")
    return sorted(changed)


def require_worktree_delta(variant):
    changed = set(subprocess.check_output(["git", "diff", "--name-only", "-z", "HEAD"]).decode().split("\0"))
    changed.discard("")
    untracked = set(subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"])
                    .decode().split("\0"))
    untracked.discard("")
    expected = CHANGED_PIN_PATHS if variant == "old" else set()
    if changed != expected or untracked:
        raise ValueError(f"Hosted source tree differs outside variant metadata: {sorted(changed)} "
                         f"untracked={sorted(untracked)}")


def inspect_variant_files(variant):
    revision = REVISIONS[variant]
    manifest = MANIFEST.read_text()
    project = PROJECT.read_text()
    inventory = json.loads(INVENTORY.read_text())
    lock = json.loads(LOCK.read_text())
    component = next(item for item in inventory["components"] if item["id"] == "textual")
    if (manifest.count(revision) != 1 or project.count(revision) != 1
            or component["revision"] != revision or component["version"] != revision[:8]
            or component["manifest_requirement"]["revision"] != revision
            or component["licence_texts"][0]["upstream_revision"] != revision):
        raise ValueError("App, package and inventory do not name the same Textual head")
    textual = next(pin for pin in lock["pins"] if pin["identity"] == "textual")
    if textual["state"] != {"revision": revision}:
        raise ValueError("The actual resolved Textual revision differs")
    return lock


def prepare(variant):
    if subprocess.check_output(["git", "status", "--porcelain"]):
        raise ValueError("The hosted checkout must begin clean")
    ROOT.mkdir(mode=0o700)
    baseline = tracked_hashes()
    old_lock = json.loads(LOCK.read_text())
    validate_pins(old_lock, old_lock, NEW)
    if variant == "old":
        MANIFEST.write_text(replace_exact(MANIFEST.read_text(), NEW, OLD))
        PROJECT.write_text(replace_exact(PROJECT.read_text(), NEW, OLD))
        inventory = json.loads(INVENTORY.read_text())
        component = next(item for item in inventory["components"] if item["id"] == "textual")
        if (component["revision"], component["version"], component["manifest_requirement"]["revision"],
                component["licence_texts"][0]["upstream_revision"]) != (NEW, NEW[:8], NEW, NEW):
            raise ValueError("The reviewed inventory source differs")
        component["revision"] = OLD
        component["version"] = OLD[:8]
        component["manifest_requirement"]["revision"] = OLD
        component["licence_texts"][0]["upstream_revision"] = OLD
        INVENTORY.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n")
        command = ["swift", "package", "--package-path", str(PACKAGE), "resolve"]
        with (ROOT / "resolve.log").open("wb") as log:
            resolved = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if resolved.returncode:
            raise ValueError(f"Guarded old-head SwiftPM resolution failed: {resolved.returncode}")
    current_lock = inspect_variant_files(variant)
    validate_pins(old_lock, current_lock, REVISIONS[variant])
    current = tracked_hashes()
    changed = source_delta(baseline, current, variant)
    require_worktree_delta(variant)
    recorded = {
        "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "variant": variant, "textual_revision": REVISIONS[variant],
        "baseline_source_sha256": baseline, "compiled_source_sha256": current,
        "changed_pin_metadata_paths": changed,
        "baseline_lock_sha256": baseline[str(LOCK)], "resolved_lock_sha256": current[str(LOCK)],
        "other_23_pins_unchanged": True,
        "host": {"uid": os.getuid(), "home": str(Path.home()), "architecture": platform.machine(),
                 "macos": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
                 "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip()},
        "diagnostic_only": True, "qualification_candidate": False,
        "scope": "Same app/test source, ten fresh mounted Copy sequences per Textual variant; no shipping claim",
    }
    (ROOT / "ab-inputs.json").write_text(json.dumps(recorded, indent=2, sort_keys=True) + "\n")
    print(f"Guarded A/B source prepared: {variant} {REVISIONS[variant]} changes={changed}")


def require_inputs(variant):
    record = json.loads((ROOT / "ab-inputs.json").read_text())
    if record["variant"] != variant or record["textual_revision"] != REVISIONS[variant]:
        raise ValueError("A/B variant or pin changed")
    if subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() != record["checkout"]:
        raise ValueError("Checkout changed after preparation")
    current = tracked_hashes()
    if current != record["compiled_source_sha256"]:
        raise ValueError("Tracked app/test source changed after preparation")
    source_delta(record["baseline_source_sha256"], current, variant)
    require_worktree_delta(variant)
    inspect_variant_files(variant)
    return record


def textual_checkout_hashes(derived, expected):
    checkouts = [path for path in (derived / "SourcePackages/checkouts").iterdir()
                 if path.name.lower() == "textual" and path.is_dir()]
    if len(checkouts) != 1:
        raise ValueError("Exact Textual Xcode source checkout is absent or ambiguous")
    checkout = checkouts[0]
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != expected:
        raise ValueError("Built Textual checkout has the wrong Git head")
    names = subprocess.check_output(["git", "-C", str(checkout), "ls-files", "-z"]).decode().split("\0")
    files = {name: digest((checkout / name).read_bytes()) for name in names if name}
    return {"revision": revision, "source_sha256": files}


def capture_build(variant):
    record = require_inputs(variant)
    derived = Path(os.environ["RUNNER_TEMP"]) / "preview-grant-app"
    products = derived / "Build/Products"
    capture(ROOT, products, "Debug", Path("MacDown2/MacDown2.xcodeproj").resolve(), "initial")
    textual = textual_checkout_hashes(derived, record["textual_revision"])
    (ROOT / "textual-checkout.json").write_text(json.dumps(textual, indent=2, sort_keys=True) + "\n")
    print(f"Captured exact built app and Textual source: {variant} {textual['revision']}")


def correlation_module():
    script = Path(__file__).with_name("verify-preview-inline-selection-correlation.py")
    spec = importlib.util.spec_from_file_location("mounted_correlation", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def selected_test_results(tree):
    results = []
    if isinstance(tree, dict):
        identifier = tree.get("nodeIdentifierURL")
        if isinstance(identifier, str) and "/SecuredMarkdownMountedTests/" in identifier:
            results.append((identifier, tree.get("result")))
        for value in tree.values():
            results.extend(selected_test_results(value))
    elif isinstance(tree, list):
        for value in tree:
            results.extend(selected_test_results(value))
    return results


def run_repeats(variant):
    record = require_inputs(variant)
    binding = json.loads((ROOT / "compiled-initial.json").read_text())
    verify(ROOT, binding)
    app = Path(binding["inputs"]["app_executable"]["path"])
    app_hash = binding["inputs"]["app_executable"]["sha256"]
    derived = Path(os.environ["RUNNER_TEMP"]) / "preview-grant-app"
    if textual_checkout_hashes(derived, record["textual_revision"]) != json.loads(
            (ROOT / "textual-checkout.json").read_text()):
        raise ValueError("Textual source checkout changed after build")
    correlation = correlation_module()
    rows = []
    for number in range(1, REPEATS + 1):
        prefix = f"repeat-{number:02d}"
        command = [
            "xcodebuild", "-project", "MacDown2/MacDown2.xcodeproj", "-scheme", "MacDown2",
            "-configuration", "Debug", "ENABLE_TESTABILITY=YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) RELEASE_PREVIEW_PROBE",
            "-destination", "platform=macOS,arch=arm64", "ONLY_ACTIVE_ARCH=YES",
            "-derivedDataPath", str(derived), "-onlyUsePackageVersionsFromResolvedFile",
            "-parallel-testing-enabled", "NO", "-resultBundlePath", str(ROOT / (prefix + ".xcresult")),
            TEST, "test-without-building",
        ]
        wrapper = [sys.executable, ".github/scripts/run-owned-app-tests.py",
                   str(ROOT / (prefix + "-diagnostics")), str(app), "--", *command]
        log_path = ROOT / (prefix + ".log")
        with log_path.open("wb") as log:
            result = subprocess.run(wrapper, stdout=log, stderr=subprocess.STDOUT)
        raw = log_path.read_bytes()
        generations, errors = correlation.inspect(raw.decode("utf-8", errors="replace"), variant=variant)
        status_path = ROOT / (prefix + "-diagnostics/status.json")
        identity_path = ROOT / (prefix + "-diagnostics/identity.json")
        status = json.loads(status_path.read_text()) if status_path.exists() else {}
        identity = json.loads(identity_path.read_text()) if identity_path.exists() else {}
        summary = {}
        selected = []
        result_path = ROOT / (prefix + ".xcresult")
        if result_path.is_dir():
            inspected = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                        "--path", str(result_path)], capture_output=True)
            if inspected.returncode == 0:
                (ROOT / (prefix + "-summary.json")).write_bytes(inspected.stdout)
                summary = json.loads(inspected.stdout)
            inspected = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                        "--path", str(result_path)], capture_output=True)
            if inspected.returncode == 0:
                (ROOT / (prefix + "-tests.json")).write_bytes(inspected.stdout)
                selected = selected_test_results(json.loads(inspected.stdout))
        selected_ids = [identifier for identifier, _ in selected]
        row = {
            "repeat": number, "variant": variant, "textual_revision": record["textual_revision"],
            "log_sha256": digest(raw), "wrapper_returncode": result.returncode,
            "owned_status": status, "owned_app_sha256": identity.get("app_sha256"),
            "owned_checkout": identity.get("checkout"),
            "xcresult_summary": summary, "selected_test_identifiers": selected_ids,
            "selected_test_results": dict(selected),
            "generations": generations, "correlation_errors": errors,
        }
        row["passed"] = (
            result.returncode == 0 and status.get("returncode") == 0
            and not status.get("timed_out") and not status.get("cancelled")
            and not status.get("app_cleanup_requested")
            and identity.get("app_sha256") == app_hash and identity.get("checkout") == record["checkout"]
            and summary.get("totalTestCount") == 4 and summary.get("passedTests") == 4
            and summary.get("failedTests") == 0 and summary.get("skippedTests") == 0
            and len(selected) == len(EXPECTED_TEST_URLS)
            and set(selected_ids) == EXPECTED_TEST_URLS
            and all(result == "Passed" for _, result in selected)
            and (TEST_URL, "Passed") in selected
            and len(generations) == 10 and not errors
        )
        (ROOT / (prefix + ".json")).write_text(json.dumps(row, indent=2, sort_keys=True) + "\n")
        rows.append(row)
        print(f"A/B {variant} repeat {number}/{REPEATS}: pass={row['passed']} "
              f"test={summary.get('passedTests')}/{summary.get('totalTestCount')} "
              f"generations={len(generations)} errors={len(errors)}", flush=True)
        if (status.get("timed_out") or status.get("cancelled") or not status
                or summary.get("totalTestCount") != 4):
            break
    verify(ROOT, binding)
    require_inputs(variant)
    if textual_checkout_hashes(derived, record["textual_revision"]) != json.loads(
            (ROOT / "textual-checkout.json").read_text()):
        raise ValueError("Textual source checkout changed during repeated Copy")
    first = next((row for row in rows if not row["passed"]), None)
    result = {
        "checkout": record["checkout"], "variant": variant, "textual_revision": record["textual_revision"],
        "app_executable_sha256": app_hash,
        "test_executable_sha256": binding["inputs"]["test_executable"]["sha256"],
        "source_map_sha256": digest((ROOT / "ab-inputs.json").read_bytes()),
        "textual_map_sha256": digest((ROOT / "textual-checkout.json").read_bytes()),
        "requested_repeats": REPEATS, "completed_repeats": len(rows),
        "passed_repeats": sum(row["passed"] for row in rows),
        "first_failure_repeat": first["repeat"] if first else None,
        "diagnostic_only": True, "qualification_candidate": False,
    }
    (ROOT / "ab-result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, sort_keys=True))
    if len(rows) != REPEATS or first:
        raise SystemExit("A/B cell failed; retained every completed raw XCResult, event log and source hash")


def main():
    if sys.flags.optimize:
        raise SystemExit("Optimized Python cannot enforce the private native host guard")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "capture", "run"])
    parser.add_argument("variant", choices=REVISIONS)
    args = parser.parse_args()
    check_host(ROOT.resolve())
    if args.phase == "prepare":
        prepare(args.variant)
    elif args.phase == "capture":
        capture_build(args.variant)
    else:
        run_repeats(args.variant)


if __name__ == "__main__":
    main()
