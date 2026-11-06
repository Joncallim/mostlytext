#!/usr/bin/env python3
"""Hosted-only before/after native editor qualification with immutable receipts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

BASELINE = "6667bc9c1cb74534eafc417d921c3a37c55628b0"
COMMON = "MacDown2/Packages/MacDownKit/Tests/HighlightingTests/CurrentLineRoleBitmapTests.swift"


def run(arguments, **kwargs):
    return subprocess.check_output(arguments, text=True, **kwargs).strip()


def inventory(root):
    names = run(["git", "ls-files", "MacDown2", ".github/scripts/run-current-line-theme-probe.py",
                 ".github/workflows/current-line-theme-probe.yml"], cwd=root).splitlines()
    names = sorted(set(names + [COMMON]))
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in names}


def qualify(root, output, configuration, baseline):
    output.mkdir()
    sources = inventory(root)
    lock = root / "MacDown2/Packages/MacDownKit/Package.resolved"
    original_lock = lock.read_bytes()
    receipt = {"checkout": run(["git", "rev-parse", "HEAD"], cwd=root),
               "configuration": configuration, "baseline": baseline,
               "source_sha256": sources, "pins": json.loads(original_lock)["pins"]}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    package = root / "MacDown2/Packages/MacDownKit"
    scratch = output / "build"
    command = ["swift", "build", "--package-path", str(package), "--scratch-path", str(scratch),
               "-c", configuration, "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
    with (output / "compile.log").open("w") as log:
        subprocess.run(command + ["--build-tests"], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=900)
    binary = Path(run(command + ["--show-bin-path"])) / "MacDownKitPackageTests.xctest/Contents/MacOS/MacDownKitPackageTests"
    developer = Path(run(["xcode-select", "-p"]))
    helper = developer / "Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
    owned = output / "owned-swiftpm-testing-helper"
    shutil.copyfile(helper, owned)
    owned.chmod(0o700)
    if owned.read_bytes() != helper.read_bytes():
        raise SystemExit("Owned native helper copy changed")
    subprocess.run(["codesign", "--force", "--sign", "-", str(owned)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(owned)], check=True)
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [helper, owned, binary]}
    environment = dict(os.environ, DYLD_FRAMEWORK_PATH=str(developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"))
    pattern = "CurrentLineRoleBitmapTests" if baseline else "EditorCoreTests|HighlightingTests|ThemesTests"
    with (output / "probe.log").open("w") as log:
        result = subprocess.run([str(owned), "--test-bundle-path", str(binary), "--testing-library", "swift-testing",
                                 "--no-parallel", "--filter", pattern], cwd=root, env=environment,
                                stdout=log, stderr=subprocess.STDOUT, timeout=600)
    (output / "status.json").write_text(json.dumps({"returncode": result.returncode}) + "\n")
    if inventory(root) != sources or lock.read_bytes() != original_lock:
        raise SystemExit("Native probe source or immutable lock changed")
    if any(hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest for name, digest in hashes.items()):
        raise SystemExit("Native execution products changed")
    receipt["execution_sha256"] = hashes
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    log = re.sub(r"\x1b\[[0-9;]*m", "", (output / "probe.log").read_text())
    if baseline:
        if result.returncode != 1 or not re.search(r"Test run with 2 tests in 1 suite failed .* with 2 issues", log):
            raise SystemExit("Baseline must execute both common bitmap controls and fail only the two missing features")
        for message in ["production theme application and draw path must paint the current row",
                        "current row needs a shape cue beyond font weight"]:
            if message not in log:
                raise SystemExit("Baseline failed for a different reason: " + message)
    else:
        if result.returncode != 0 or not re.search(r"Test run with [1-9][0-9]* tests in [1-9][0-9]* suites passed", log):
            raise SystemExit("All selected real editor/highlighter/theme tests must execute and pass")
        for name in ["anAppliedThemePaintsAndRemovesTheCurrentLineInTheRealScrolledEditor",
                     "aShapeIdentifiesThePrimaryLineEvenWhenTheEditorFontIsAlreadyBold",
                     "currentLineDrawingKeepsTenMiBViewportWorkBounded",
                     "liveChromeUsesTheSingleResolvedPaletteWithoutEditingSource"]:
            if not re.search(r"Test " + name + r"\(\) passed", log):
                raise SystemExit("Required native control did not pass: " + name)
        if "CURRENT-LINE-PHASE" not in log:
            raise SystemExit("Real viewport draw measurement did not execute")
    print(("Baseline" if baseline else "Candidate") + " exact native result/source/pins verified: " + configuration)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("configuration", choices=["debug", "release"])
    args = parser.parse_args()
    if os.environ.get("CI") != "true" or run(["sw_vers", "-productVersion"]).split(".")[0] != "26":
        raise SystemExit("This native execution requires the hosted macOS 26 job")
    repo = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=False)
    baseline = args.output / "baseline-checkout"
    subprocess.run(["git", "worktree", "add", "--detach", str(baseline), BASELINE], cwd=repo, check=True)
    common = (repo / COMMON).read_bytes()
    (baseline / COMMON).write_bytes(common)
    qualify(baseline, args.output / "baseline", args.configuration, True)
    if (baseline / COMMON).read_bytes() != common or (repo / COMMON).read_bytes() != common:
        raise SystemExit("Before/after bitmap fixture bytes differ")
    qualify(repo, args.output / "candidate", args.configuration, False)


if __name__ == "__main__":
    main()
