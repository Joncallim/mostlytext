#!/usr/bin/env python3
"""Hosted-only exact-model attachment publication controls, before and after repair."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

BASELINE = "4fda20fe5e7ba79b756a3b4bac97db284ebe0933"
COMMON = "MacDown2/MacDown2Tests/TextualAttachmentPublicationTests.swift"
MODEL = "Sources/Textual/Internal/Attachment/WithAttachments.swift"
CONTROLS = [
    "Plain source must replace the prior resolved image source",
    "Cancelled attachment completion must not replace newer source",
    "Older attachment completion must retain the latest request's source",
    "Already cancelled requests must not clear or replace current content",
]
FUNCTIONS = [
    "plainSourceReplacesThePreviouslyResolvedImageSource",
    "cancelledOlderReadCannotPublishOverNewerSource",
    "olderUncancelledReadCannotPublishOverNewerSource",
    "requestCancelledBeforeEntryCannotReplaceCurrentContent",
]


def run(arguments, **kwargs):
    return subprocess.check_output(arguments, text=True, **kwargs).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    names = run(["git", "ls-files", "MacDown2", ".github/scripts/run-attachment-publication-probe.py",
                 ".github/scripts/run-owned-app-tests.py", ".github/scripts/test-run-owned-app-tests.py",
                 ".github/scripts/test-attachment-publication-pin-review.py",
                 ".github/workflows/attachment-publication-probe.yml"], cwd=root).splitlines()
    return {name: digest(root / name) for name in sorted(set(names + [COMMON]))}


def owners(pins):
    return {p["identity"]: (p["location"], p["state"]["revision"]) for p in pins}


# Exact independent updates reviewed with the query capture-name cache unit.
REVIEWED_INDEPENDENT_PIN_UPDATES = {
    "neon": ("https://github.com/Joncallim/Neon",
             "cd14f22ae8f8402b175a0bafd87560b78c7549e9", "72174c8de8f28c957fd48850b90de99899b709ee"),
    "swifttreesitter": ("https://github.com/Joncallim/SwiftTreeSitter",
                       "0beea992c4246f93a122de846c8611c9be19aeb7", "f2163a8bc5d0f1ce76b4cead48ce0f3ade4aa9f3"),
}


def reviewed_model_pin_delta(original, current):
    """Other exact reviewed updates do not qualify a model repair or permit unknown pins."""
    before, after = owners(original), owners(current)
    if len(before) != len(original) or len(after) != len(current):
        raise SystemExit("Duplicate dependency identities cannot qualify exact pin review")
    previous, candidate = before.get("textual"), after.get("textual")
    if previous is None or candidate is None or previous[0] != candidate[0]:
        raise SystemExit("The original Textual model owner must remain unchanged")
    differences = {name for name in before.keys() | after.keys() if before.get(name) != after.get(name)}
    independent = {}
    for name in sorted(differences - {"textual"}):
        expected = REVIEWED_INDEPENDENT_PIN_UPDATES.get(name)
        if expected is None or before.get(name) != (expected[0], expected[1]) or after.get(name) != (expected[0], expected[2]):
            raise SystemExit("An unreviewed independent dependency changed: " + name)
        independent[name] = {"original": before[name], "candidate": after[name]}
    return "textual" in differences, independent


def prepare(root, output, common):
    package = output / "probe"
    destination = package / "Tests/AttachmentPublicationTests"
    destination.mkdir(parents=True)
    actual = root / "MacDown2/Packages/MacDownKit"
    fixture = destination / Path(COMMON).name
    fixture.write_bytes(common)
    manifest = ('// swift-tools-version: 6.2\nimport PackageDescription\n'
                'let package = Package(name: "AttachmentPublicationProbe", platforms: [.macOS(.v26)], '
                'dependencies: [.package(path: ' + json.dumps(str(actual)) + ')], targets: [\n'
                '.testTarget(name: "AttachmentPublicationTests", dependencies: '
                '[.product(name: "Preview", package: "MacDownKit")])])\n')
    (package / "Package.swift").write_text(manifest)
    pins = json.loads((actual / "Package.resolved").read_text())["pins"]
    (package / "Package.resolved").write_text(json.dumps({"version": 2, "pins": pins}, indent=2) + "\n")
    return package, fixture, manifest, pins


def qualify(root, controls_root, output, configuration, common, baseline):
    output.mkdir()
    sources = inventory(root)
    package, fixture, manifest, pins = prepare(root, output, common)
    (output / "probe-Package.swift").write_text(manifest)
    lock = root / "MacDown2/Packages/MacDownKit/Package.resolved"
    original_lock = lock.read_bytes()
    receipt = {"checkout": run(["git", "rev-parse", "HEAD"], cwd=root),
               "configuration": configuration, "baseline": baseline,
               "os": run(["sw_vers", "-productVersion"]), "swift": run(["swift", "--version"]),
               "source_sha256": sources, "pins": pins, "common_sha256": digest(fixture),
               "probe_manifest_sha256": hashlib.sha256(manifest.encode()).hexdigest(),
               "orchestration_sha256": inventory(controls_root)}
    record = output / "receipt.json"
    record.write_text(json.dumps(receipt, indent=2) + "\n")
    scratch = output / "build"
    command = ["swift", "build", "--package-path", str(package), "--scratch-path", str(scratch),
               "-c", configuration, "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
    with (output / "compile.log").open("w") as log:
        subprocess.run(command + ["--build-tests"], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=900)
    binary = Path(run(command + ["--show-bin-path"])) / "AttachmentPublicationProbePackageTests.xctest/Contents/MacOS/AttachmentPublicationProbePackageTests"
    textual_pin = next(p for p in pins if p["identity"] == "textual")
    textual = scratch / "checkouts/textual"
    if run(["git", "rev-parse", "HEAD"], cwd=textual) != textual_pin["state"]["revision"]:
        raise SystemExit("Actual Textual checkout differs from its immutable pin")
    for source, name in [(MODEL, "actual-WithAttachments.swift"), ("LICENSE", "actual-Textual-LICENSE")]:
        raw = subprocess.check_output(["git", "show", "HEAD:" + source], cwd=textual)
        if (textual / source).read_bytes() != raw:
            raise SystemExit("Actual Textual source/license differs from its pinned Git object")
        (output / name).write_bytes(raw)
        receipt[name + "_sha256"] = hashlib.sha256(raw).hexdigest()
    developer = Path(run(["xcode-select", "-p"]))
    helper = developer / "Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
    owned = output / "owned-swiftpm-testing-helper"
    shutil.copyfile(helper, owned)
    owned.chmod(0o700)
    if owned.read_bytes() != helper.read_bytes():
        raise SystemExit("Owned native helper copy changed before signing")
    subprocess.run(["codesign", "--force", "--sign", "-", str(owned)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(owned)], check=True)
    hashes = {str(path): digest(path) for path in [helper, owned, binary]}
    receipt["execution_sha256"] = hashes
    record.write_text(json.dumps(receipt, indent=2) + "\n")
    environment = dict(os.environ, DYLD_FRAMEWORK_PATH=str(developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"))
    with (output / "probe.log").open("w") as log:
        result = subprocess.run([sys.executable, str(controls_root / ".github/scripts/run-owned-app-tests.py"),
                                 str(output / "diagnostics"), str(owned), "--", str(owned),
                                 "--test-bundle-path", str(binary), "--testing-library", "swift-testing",
                                 "--no-parallel", "--filter", "TextualAttachmentPublicationTests"],
                                cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=660)
    (output / "status.json").write_text(json.dumps({"returncode": result.returncode}) + "\n")
    status = json.loads((output / "diagnostics/status.json").read_text())
    if status["timed_out"] or status["cancelled"] or status["returncode"] != result.returncode:
        raise SystemExit("Incomplete or cancelled native controls cannot qualify")
    if inventory(controls_root) != receipt["orchestration_sha256"]:
        raise SystemExit("Native orchestration source changed during execution")
    if inventory(root) != sources or lock.read_bytes() != original_lock or fixture.read_bytes() != common:
        raise SystemExit("Native probe source, fixture or immutable lock changed")
    if (package / "Package.swift").read_text() != manifest:
        raise SystemExit("Actual-product probe manifest changed")
    if owners(json.loads((package / "Package.resolved").read_text())["pins"]) != owners(pins):
        raise SystemExit("Focused native probe dependency owners/revisions changed")
    for source, name in [(MODEL, "actual-WithAttachments.swift"), ("LICENSE", "actual-Textual-LICENSE")]:
        if digest(textual / source) != receipt[name + "_sha256"]:
            raise SystemExit("Pinned native model/license changed during execution")
    if any(digest(Path(name)) != value for name, value in hashes.items()):
        raise SystemExit("Native execution products changed")
    log = re.sub(r"\x1b\[[0-9;]*m", "", (output / "probe.log").read_text())
    outcome = "failed" if baseline else "passed"
    summary = r"Test run with 4 tests in 1 suite " + outcome
    if baseline:
        summary += r" .* with 4 issues"
    if result.returncode != (1 if baseline else 0) or not re.search(summary, log):
        raise SystemExit("All four exact native controls must complete with their required result")
    for name in FUNCTIONS:
        if not re.search(r"Test " + name + r"\(\) " + outcome, log):
            raise SystemExit("Native control missing required outcome: " + name)
    if baseline and any(message not in log for message in CONTROLS):
        raise SystemExit("Baseline failed for an unrelated reason")
    receipt["verified_complete_result"] = outcome
    record.write_text(json.dumps(receipt, indent=2) + "\n")
    print(("Baseline" if baseline else "Candidate") + " actual-model controls verified: " + configuration)
    return pins, receipt["actual-Textual-LICENSE_sha256"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("configuration", choices=["debug", "release"])
    args = parser.parse_args()
    if os.environ.get("CI") != "true" or run(["sw_vers", "-productVersion"]).split(".")[0] != "26":
        raise SystemExit("Native execution requires the hosted macOS 26 job")
    repo = Path(__file__).resolve().parents[2]
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    common = (repo / COMMON).read_bytes()
    baseline = args.output / "baseline-checkout"
    subprocess.run(["git", "worktree", "add", "--detach", str(baseline), BASELINE], cwd=repo, check=True)
    (baseline / COMMON).write_bytes(common)
    original, license_hash = qualify(baseline, repo, args.output / "baseline", args.configuration, common, True)
    current = json.loads((repo / "MacDown2/Packages/MacDownKit/Package.resolved").read_text())["pins"]
    model_changed, independent = reviewed_model_pin_delta(original, current)
    (args.output / "dependency-delta.json").write_text(json.dumps({
        "model_revision_changed": model_changed, "independently_reviewed_updates": independent,
        "scope": "Recorded exact reviewed updates; model proof does not approve other dependency changes"
    }, indent=2) + "\n")
    if not model_changed:
        (args.output / "baseline-only.json").write_text(json.dumps({"repair_evaluated": False,
            "reason": "Pinned original model only; candidate repair is not implemented"}) + "\n")
        print("Original-model baseline only; no candidate repair qualified")
        return
    _, candidate_license = qualify(repo, repo, args.output / "candidate", args.configuration, common, False)
    if candidate_license != license_hash:
        raise SystemExit("Original Textual MIT license changed")
    if (repo / COMMON).read_bytes() != common or (baseline / COMMON).read_bytes() != common:
        raise SystemExit("Before/after tests differ")


if __name__ == "__main__":
    main()
