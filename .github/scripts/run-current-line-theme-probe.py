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
import sys

BASELINE = "6667bc9c1cb74534eafc417d921c3a37c55628b0"
COMMON = "MacDown2/Packages/MacDownKit/Tests/HighlightingTests/CurrentLineRoleBitmapTests.swift"


def run(arguments, **kwargs):
    return subprocess.check_output(arguments, text=True, **kwargs).strip()


def inventory(root):
    names = run(["git", "ls-files", "MacDown2", ".github/scripts/run-current-line-theme-probe.py",
                 ".github/workflows/current-line-theme-probe.yml",
                 ".github/scripts/run-owned-app-tests.py",
                 ".github/scripts/test-run-owned-app-tests.py"], cwd=root).splitlines()
    names = sorted(set(names + [COMMON]))
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in names}


def prepare_test_package(root, output, baseline):
    """Keep actual library products and exact tests, without compiling unrelated tests."""
    package = output / "probe"
    package.mkdir()
    actual = root / "MacDown2/Packages/MacDownKit"
    copied = {}
    groups = {"HighlightingTests": ["Highlighting"]} if baseline else {
        "EditorCoreTests": ["EditorCore", "JSONSupport"],
        "HighlightingTests": ["Highlighting"], "ThemesTests": ["Themes"]}
    targets = []
    for name, dependencies in groups.items():
        destination = package / "Tests" / name
        destination.mkdir(parents=True)
        tests = [root / COMMON] if baseline else sorted((actual / "Tests" / name).rglob("*.swift"))
        for source in tests:
            relative = source.relative_to(actual)
            target = package / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            raw = source.read_bytes()
            if re.search(rb"Bundle\.module|#filePath|#fileID|#file\b", raw):
                raise SystemExit("A source-relative/resource test needs an explicit packaging decision: " + str(source))
            target.write_bytes(raw)
            copied[str(relative)] = hashlib.sha256(raw).hexdigest()
        products = ", ".join('.product(name: ' + json.dumps(product) + ', package: "MacDownKit")' for product in dependencies)
        targets.append('.testTarget(name: ' + json.dumps(name) + ', dependencies: [' + products + '])')
    manifest = ('// swift-tools-version: 6.2\nimport PackageDescription\n'
                'let package = Package(name: "CurrentLineThemeProbe", platforms: [.macOS(.v26)], '
                'dependencies: [.package(path: ' + json.dumps(str(actual)) + ')], targets: [\n' +
                ',\n'.join(targets) + '\n])\n')
    (package / "Package.swift").write_text(manifest)
    pins = json.loads((actual / "Package.resolved").read_text())["pins"]
    (package / "Package.resolved").write_text(json.dumps({"version": 2, "pins": pins}, indent=2) + "\n")
    return package, copied, hashlib.sha256(manifest.encode()).hexdigest()


def diagnose_performance_failure(root, output, binary, helper, environment):
    """Retain isolated results without changing the failed complete selection's verdict."""
    if os.environ.get("CI") != "true":
        raise SystemExit("Performance diagnostics require the owned hosted job")
    destination = output / "performance-diagnostic"
    destination.mkdir()
    inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [binary, helper]}
    metadata = []
    for command in [["sw_vers"], ["xcodebuild", "-version"],
                    ["sysctl", "hw.model", "hw.ncpu", "hw.memsize", "machdep.cpu.brand_string"]]:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        metadata.append({"command": command, "returncode": result.returncode,
                         "stdout": result.stdout, "stderr": result.stderr})
    (destination / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    results = []
    for label, selection in [("parse-only", "mainThreadParseBudgetDocumented"),
                             ("performance-suite", "HighlightPerformanceTests")]:
        diagnostics = destination / (label + "-diagnostics")
        with (destination / (label + ".log")).open("w") as log:
            result = subprocess.run([
                sys.executable, str(root / ".github/scripts/run-owned-app-tests.py"),
                str(diagnostics), str(helper), "--", str(helper),
                "--test-bundle-path", str(binary), "--testing-library", "swift-testing",
                "--no-parallel", "--filter", selection,
            ], cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=660)
        status = json.loads((diagnostics / "status.json").read_text())
        results.append({"label": label, "selection": selection,
                        "supervisor_returncode": result.returncode, "owned_status": status})
        (destination / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        if status["timed_out"] or status["cancelled"]:
            break
    if any(hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest for name, digest in inputs.items()):
        raise SystemExit("A diagnostic execution product changed")
    (destination / "execution-sha256.json").write_text(json.dumps(inputs, indent=2) + "\n")
    print("Isolated performance results retained; the original complete selection remains failed")


def qualify(root, output, configuration, baseline):
    output.mkdir()
    sources = inventory(root)
    lock = root / "MacDown2/Packages/MacDownKit/Package.resolved"
    original_lock = lock.read_bytes()
    package, copied, manifest_digest = prepare_test_package(root, output, baseline)
    receipt = {"copied_test_sha256": copied, "probe_manifest_sha256": manifest_digest, "checkout": run(["git", "rev-parse", "HEAD"], cwd=root),
               "configuration": configuration, "baseline": baseline,
               "source_sha256": sources, "pins": json.loads(original_lock)["pins"]}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    scratch = output / "build"
    command = ["swift", "build", "--package-path", str(package), "--scratch-path", str(scratch),
               "-c", configuration, "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
    with (output / "compile.log").open("w") as log:
        subprocess.run(command + ["--build-tests"], stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=900)
    binary = Path(run(command + ["--show-bin-path"])) / "CurrentLineThemeProbePackageTests.xctest/Contents/MacOS/CurrentLineThemeProbePackageTests"
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
    if any(hashlib.sha256((package / name).read_bytes()).hexdigest() != digest for name, digest in copied.items()):
        raise SystemExit("Copied native test bytes changed")
    if hashlib.sha256((package / "Package.swift").read_bytes()).hexdigest() != manifest_digest:
        raise SystemExit("Focused actual-product manifest changed")
    observed_pins = json.loads((package / "Package.resolved").read_text())["pins"]
    owners = lambda rows: {p["identity"]: (p["location"], p["state"]["revision"]) for p in rows}
    if owners(observed_pins) != owners(receipt["pins"]):
        raise SystemExit("Focused native probe dependency owners/revisions changed")
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
        if result.returncode != 0 or not re.search(r"Test run with 1106 tests in 151 suites passed", log):
            if configuration == "release" and "Suite HighlightPerformanceTests failed" in log:
                diagnose_performance_failure(root, output, binary, owned, environment)
            raise SystemExit("All selected real editor/highlighter/theme tests must execute and pass")
        for name in ["preEditPlainParagraphWindowRefusesStructuralEdits",
                     "oracleRootWindowsAndInlineCapturesAfterEdits",
                     "anAppliedThemePaintsAndRemovesTheCurrentLineInTheRealScrolledEditor",
                     "aShapeIdentifiesThePrimaryLineEvenWhenTheEditorFontIsAlreadyBold",
                     "currentLineDrawingKeepsTenMiBViewportWorkBounded",
                     "liveChromeUsesTheSingleResolvedPaletteWithoutEditingSource",
                     "captureNamesRetainNamedAndGlobalDirectiveSemantics",
                     "oneQueryKeepsCurrentTreeRangesWhenSourceOffsetsChange",
                     "independentCursorsShareAnImmutableQueryConcurrently",
                     "denseInlineEditsKeepFreshCapturesAndPreviouslyRetainedSnapshots"]:
            if not re.search(r"Test " + name + r"\(\) passed", log):
                raise SystemExit("Required native control did not pass: " + name)
        if 'Test "closing emphasis after a word at line end does not insert an extra delimiter" passed' not in log:
            raise SystemExit("Required line-end delimiter control did not pass")
        if not re.search(
            r"Test performanceCorpusReachesItsRequestedUTF8Size\(_:\) with 2 test cases passed", log
        ):
            raise SystemExit("Both full-size performance fixture controls must pass")
        for name in ["handled assist through the adapter within a known anchor stays within the keystroke budget",
                     "unresolved assist beyond the fence scan cap stays bounded"]:
            if not re.search(r'Test "' + re.escape(name) + r'" passed', log):
                raise SystemExit("Required bounded assist control did not pass: " + name)
        if "CURRENT-LINE-PHASE" not in log:
            raise SystemExit("Real viewport draw measurement did not execute")
        if "HIGHLIGHT_PHASE sourceUTF8=1000008 setup=" not in log:
            raise SystemExit("Actual unchanged full-highlight phase observation did not execute")
    print(("Baseline" if baseline else "Candidate") + " exact native result/source/pins verified: " + configuration)


def orientation_mutation(repo, output, configuration):
    """Prove the unchanged orientation threshold still rejects inverted glyphs."""
    path = repo / "MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorGutterView.swift"
    original = path.read_bytes()
    needle = b"cgContext.textMatrix = Self.coreTextMatrix(forFlippedView: isFlipped)"
    if original.count(needle) != 1:
        raise SystemExit("The exact production orientation assignment changed")
    candidate = output / "candidate"
    command = ["swift", "build", "--package-path", str(candidate / "probe"),
               "--scratch-path", str(candidate / "build"), "-c", configuration,
               "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
    binary = Path(run(command + ["--show-bin-path"])) / "CurrentLineThemeProbePackageTests.xctest/Contents/MacOS/CurrentLineThemeProbePackageTests"
    owned = candidate / "owned-swiftpm-testing-helper"
    developer = Path(run(["xcode-select", "-p"]))
    environment = dict(os.environ, DYLD_FRAMEWORK_PATH=str(developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"))
    records = []
    for mutation in [True, False]:
        name = "orientation-mutant" if mutation else "orientation-restored"
        try:
            path.write_bytes(original.replace(needle, b"cgContext.textMatrix = .identity") if mutation else original)
            with (output / (name + "-compile.log")).open("w") as log:
                subprocess.run(command + ["--build-tests"], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=900)
            with (output / (name + ".log")).open("w") as log:
                result = subprocess.run([str(owned), "--test-bundle-path", str(binary), "--testing-library", "swift-testing",
                                         "--no-parallel", "--filter", "EditorGutterViewDrawPathTests"],
                                        cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=120)
            records.append({"phase": name, "returncode": result.returncode,
                            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "host_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
            (output / "orientation-results.json").write_text(json.dumps(records, indent=2) + "\n")
            log = re.sub(r"\x1b\[[0-9;]*m", "", (output / (name + ".log")).read_text())
            if mutation:
                if result.returncode != 1 or not re.search(r"Test run with 1 test in 1 suite failed .* with 1 issue", log):
                    raise SystemExit("The real inverted-glyph mutant must fail exactly the orientation assertion")
                if "the production-drawn '2' must be upright" not in log:
                    raise SystemExit("Orientation mutant failed for an unrelated reason")
            elif result.returncode != 0 or "Test run with 1 test in 1 suite passed" not in log:
                raise SystemExit("The restored real orientation control must execute and pass")
        finally:
            path.write_bytes(original)
    if inventory(repo) != json.loads((candidate / "receipt.json").read_text())["source_sha256"]:
        raise SystemExit("Source changed after the orientation mutation/restore")
    print("Actual inverted-glyph mutant fails; restored production glyph passes: " + configuration)


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
    orientation_mutation(repo, args.output, args.configuration)


if __name__ == "__main__":
    main()
