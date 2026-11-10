#!/usr/bin/env python3
"""Bind actual native app execution to the checkout inputs and configuration."""
import argparse
import hashlib
import json
import os
import platform
import pwd
import sys
from pathlib import Path
import re
import subprocess
from preview_compiled_inputs import PHASES, capture as capture_compiled, check_host, verify_execution

if sys.flags.optimize:
    raise SystemExit("Optimized Python is refused before Preview diagnostic preparation")


def check_diagnostic_host(root):
    check_host(root)


def verify_native_architecture(receipt, identity, architectures):
    if receipt.get("execution_architecture") != "arm64" or receipt.get("only_active_arch") is not True:
        raise SystemExit("The native Preview receipt must identify Apple Silicon execution")
    if architectures != ["arm64"]:
        raise SystemExit("The actual Preview app must contain exactly its executed architecture")
    command = identity.get("command", [])
    if (not command or command[0] != "xcodebuild" or "test-without-building" not in command
            or [c for c in command if c.startswith("ONLY_ACTIVE_ARCH=")] != ["ONLY_ACTIVE_ARCH=YES"]):
        raise SystemExit("The owned native command must preserve the active-architecture build policy")
    destinations = [i for i, value in enumerate(command) if value == "-destination"]
    if (len(destinations) != 1 or destinations[0] + 1 >= len(command)
            or command[destinations[0] + 1] != "platform=macOS,arch=arm64"):
        raise SystemExit("The owned native command must select its actual Apple Silicon destination")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("configuration", choices=["Debug", "Release"])
parser.add_argument("--pair", choices=["revision", "viewport", "disappear"], required=True)
parser.add_argument("--verify", action="store_true")
parser.add_argument("--require-result", action="store_true")
parser.add_argument("--capture-compiled", choices=sorted(PHASES))
parser.add_argument("--verify-compiled", choices=sorted(PHASES))
args = parser.parse_args()
check_diagnostic_host(args.output.resolve())
repo = Path(__file__).resolve().parents[2]
if os.environ.get("MOSTLYTEXT_PREVIEW_RESOURCE_TRACE") != "1" or os.environ.get("TEST_RUNNER_MOSTLYTEXT_PREVIEW_RESOURCE_TRACE") != "1":
    raise SystemExit("The diagnostic workflow must enable the actual application child trace explicitly")
if platform.machine() != "arm64":
    raise SystemExit("This native Preview qualification requires an Apple Silicon worker")
paths = subprocess.check_output([
    "git", "ls-files", "-z", "MacDown2", ".github/scripts/verify-preview-grant-probe.py",
    ".github/workflows/preview-grant-probe.yml", ".github/scripts/preview_compiled_inputs.py", ".github/scripts/test-preview-compiled-inputs.py", ".github/scripts/test-preview-diagnostic-host.py", ".github/scripts/check-preview-parsed-frame.py", ".github/scripts/test-preview-grant-tripwire.py", ".github/scripts/test-preview-native-architecture.py", ".github/scripts/test-preview-suite-contract.py", ".github/scripts/run-preview-grant-probe.py", ".github/scripts/run-owned-app-tests.py", ".github/scripts/test-run-owned-app-tests.py",
    "planning/downstream/evidence/actual-app-hosted-plan-2026-11-07",
], cwd=repo).decode().split("\0")
digests = {name: hashlib.sha256((repo / name).read_bytes()).hexdigest() for name in paths if name}
lock = repo / "MacDown2/Packages/MacDownKit/Package.resolved"
pins = json.loads(lock.read_text())["pins"]
receipt = {
    "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "configuration": args.configuration,
    "mutation_pair": args.pair,
    "testability": True,
    "diagnostic_only": False,
    "qualification_candidate": True,
    "current_main_baseline": "a46c57c4b62376b67492cf67421a4961fdf55c1c",
    "resource_trace_enabled": True,
    "execution_architecture": "arm64",
    "only_active_arch": True,
    "additional_compilation_condition": "RELEASE_PREVIEW_PROBE",
    "source_sha256": digests,
    "pins": pins,
    "scope": "Current-main Preview qualification candidate; first outcomes and all six pairs required, without a sole historical cause or final release claim",
    "renderer_preference_observer": False,
    "fixture_window_lifetime_observer": True,
}
path = args.output / "receipt.json"
if args.verify:
    if json.loads(path.read_text()) != receipt:
        raise SystemExit("Actual native app source, configuration or immutable pins changed")
    if args.capture_compiled:
        capture_compiled(args.output, Path(os.environ['RUNNER_TEMP']) / 'preview-grant-app/Build/Products',
                         args.configuration, repo / 'MacDown2/MacDown2.xcodeproj', args.capture_compiled)
    if args.verify_compiled:
        verify_execution(args.output, args.configuration, args.verify_compiled)
    if args.require_result:
        for phase in ['initial', 'selection', args.pair + '-mutant', args.pair + '-restored']:
            binding = json.loads((args.output / ('compiled-' + phase + '.json')).read_text())
            proof = json.loads((args.output / ('compiled-' + phase + '-verified.json')).read_text())
            if (binding['phase'] != phase or binding['configuration'] != args.configuration
                    or proof['phase'] != phase or proof['configuration'] != args.configuration
                    or proof['compiled_inputs_unchanged_after'] is not True
                    or proof['actual_owned_app_matches_captured_executable'] is not True):
                raise SystemExit('Compiled phase was omitted, changed or retargeted')
            count = ((61 if args.configuration == 'Release' else 60) if phase == 'initial' else
                     1 if phase == 'selection' or args.pair == 'viewport' else 4)
            failed = 1 if phase.endswith('-mutant') else 0
            wanted = {'totalTestCount': count, 'passedTests': count - failed, 'failedTests': failed,
                      'skippedTests': 0, 'expectedFailures': 0}
            if any(type(proof['actual_summary'].get(k)) is not int or proof['actual_summary'][k] != v for k, v in wanted.items()):
                raise SystemExit('Actual result bundle does not contain the complete exact phase outcome: ' + phase)
            owned = proof['actual_owned']
            if (owned['returncode'] != (65 if failed else 0) or owned['timed_out'] or owned['cancelled']
                    or owned['app_cleanup_requested']):
                raise SystemExit('Actual compiled phase did not finish with its expected owned result')
        identity = json.loads((args.output / "diagnostics/identity.json").read_text())
        architectures = subprocess.check_output(["lipo", "-archs", identity["app"]], text=True).split()
        verify_native_architecture(receipt, identity, architectures)
        app_digest = hashlib.sha256(Path(identity["app"]).read_bytes()).hexdigest()
        if app_digest != identity["app_sha256"]:
            raise SystemExit("The final actual app differs from the original owned executable")
        (args.output / "native-architecture.json").write_text(json.dumps({
            "execution_architecture": "arm64", "binary_architectures": architectures,
            "only_active_arch": True, "app_sha256": app_digest,
        }, indent=2) + "\n")
        log = re.sub(r"\x1b\[[0-9;]*m", "", (args.output / "probe.log").read_text())
        suites = ["Preview directory grant lifetime", "Preview resource admission", "Preview window resource ownership",
                  "Immutable bounded HTML scheme delivery", "Secured HTML native routing", "Secured Markdown mounted attachment",
                  "Secured Preview ImageIO admission", "Secured Preview observed network denial",
                  "Secured Markdown stable viewport", "Secured Markdown source binding",
                  "Preview folder selection commands", "Production Preview resource routing",
                  "PreviewDisplayCache", "Preview resource composition ownership",
                  "HTML Preview real response encodings",
                  "Preview image decoded-output admission", "Pinned Textual image interception"]
        if args.configuration == "Release":
            suites.append("Preview Release resource probe")
        for suite in suites:
            if not re.search(r'Suite "' + re.escape(suite) + r'" passed' , log):
                raise SystemExit(suite + " did not execute successfully")
        count = 61 if args.configuration == "Release" else 60
        if not re.search(r"Test run with " + str(count) + r" tests in " + str(len(suites)) + r" suites passed", log):
            raise SystemExit("Every selected consumer test must finish; partial restarts are not accepted")
        ownership = re.findall(
            r"NATIVE_COPY_OWNERSHIP oldAcceptedStale=true fixedRefusedNoWrite=true freshActualWrite=true "
            r"seeded=(\d+) refused=(\d+) fresh=(\d+)", log
        )
        if len(ownership) != 1 or not (int(ownership[0][0]) < int(ownership[0][1]) < int(ownership[0][2])):
            raise SystemExit("Actual no-write counterexample and fresh native Copy ownership must execute once")
        for function in [
            "staleNavigationCallbacksCannotSettleARecoveredSavedPage",
            "aNoWriteNativeCopyCannotReuseAnEarlierImage",
            "fileStoreBOMDocumentsRenderAsUTF8WithoutRewritingOriginalBytes",
            "nonUTF8HTMLResourcesKeepBOMBytesAndAuthoritativeResponseProtection",
            "realSubresourcesKeepTheirMIMETypesAndUnknownHTMLIsNotAnImage",
            "canonicallyEquivalentPublishedBytesCannotBorrowTheCurrentGrant",
            "pendingPublishedSourceRetiresThePriorLoadAndKeepsPreviewMounted",
            "absentParseRetiresItsPriorLoadWithoutRemovingReadableContent",
            "originIsReservedBeforeTheCommandTaskCanRun",
            "aHeldChoiceRemainsWithItsWindowWhenAnotherWindowBecomesKey",
            "sameTextSaveAsRejectsAnOlderHeldFolderChoice",
            "rootAwayAndBackCannotReviveAPendingChoice",
            "anOlderCancellationCannotClearANewerPendingSelection",
            "theRealFolderSheetFinishesWhenItsOriginWindowCloses",
            "theRealMarkdownWindowCopiesGrantedImagesAndRevokesThemOnSaveAs",
            "theRealHTMLPaneUsesImmutableHandlersAndPreservesSourceRenderedSwitching",
            "cancellationAfterBackingAcquisitionCannotPublishAFolderGrant",
            "identicalVisibleBlocksFromAnotherParserCannotKeepThePreviousSourceFrame",
            "equalRevisionsFromAnotherParserCannotReusePublishedContributions",
        ]:
            if not re.search(r"Test " + re.escape(function) + r"\(\) passed", log):
                raise SystemExit("Required production resource control did not pass: " + function)
        if "PREVIEW_NETWORK_CONTROL live=true loaded=true deniedRequests=0" not in log:
            raise SystemExit("Independent live listener and actual WebKit containment did not execute")
        if args.configuration == "Release" and "PREVIEW_RELEASE_PROBE sourceBytes=4194304" not in log:
            raise SystemExit("Optimized maximum-source phase observation did not execute")
        mutation = json.loads((args.output / "parsed-frame-results.json").read_text())
        expected = ["revision-mutant", "revision-restored", "viewport-mutant", "viewport-restored",
                    "disappear-mutant", "disappear-restored"]
        expected = [phase for phase in expected if phase.startswith(args.pair + "-")]
        if len(mutation) != 2 or [row["phase"] for row in mutation] != expected:
            raise SystemExit("The selected actual mutation/restoration proof is incomplete")
        for mutant, restored in zip(mutation[::2], mutation[1::2]):
            if mutant["returncode"] == 0 or restored["returncode"] != 0:
                raise SystemExit("Actual native counterfactual or restored control has the wrong result")
            if mutant["app_sha256"] == restored["app_sha256"]:
                raise SystemExit("The actual application did not change for a counterfactual")
            if (mutant["original_app_sha256"] != restored["original_app_sha256"]
                    or restored["app_sha256"] != restored["original_app_sha256"]):
                raise SystemExit("The restored executable does not match its unmodified baseline")
            if restored["source_sha256"] != receipt["source_sha256"]["MacDown2/MacDown2/SecuredMarkdownResourceHost.swift"]:
                raise SystemExit("The final tested host source was not restored exactly")
    print("Exact actual-app inputs, configuration, pins and requested execution verified")
else:
    args.output.mkdir(parents=True, exist_ok=True)
    with path.open("x") as output:
        json.dump(receipt, output, indent=2)
        output.write("\n")
    print("Recorded actual-app source and immutable pins; execution is still pending")
