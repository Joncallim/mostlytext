#!/usr/bin/env python3
"""Select one unchanged original journey using the qualified hosted controller."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

QUALIFIED_MAIN = "6b49777d0f36c3d7a23cd0089e0823da1986660a"
JOURNEYS = {
    "native-tabs-dirty-close": "MacDown2UITests/TabLifecycleUITests/testOpenFilesDirtyClosePromptAndRestore",
    "native-tabs-quick-open": "MacDown2UITests/TabLifecycleUITests/testQuickOpenReactivatesAnAlreadyOpenBackgroundTab",
    "external-conflict-close": "MacDown2UITests/ExternalFileChangesUITests/testConflictCloseUseDiskClosesWithoutDiscardingTheExternalVersion",
}
EXTRA_INPUTS = [
    ".github/scripts/run-hosted-critical-journey.py",
    ".github/scripts/test-hosted-critical-journey.py",
    ".github/workflows/hosted-critical-journeys.yml",
]


def main():
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python is refused before critical-journey preparation")
    if not re.fullmatch(r"[0-9a-f]{40}", QUALIFIED_MAIN):
        raise RuntimeError("Critical journeys are held until verified PR122 qualification and actual main intake")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "execute"])
    parser.add_argument("--journey", choices=JOURNEYS, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("qualified_original_controller", Path(__file__).with_name("run-hosted-original-focus.py"))
    controller = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(controller)
    controller.QUALIFIED_MAIN = QUALIFIED_MAIN
    controller.SELECTED = JOURNEYS[args.journey]
    root = Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-focus"
    guard_spec = importlib.util.spec_from_file_location("critical_journey_host_guard", Path(__file__).with_name("prepare-hosted-public-focus.py"))
    guard = importlib.util.module_from_spec(guard_spec)
    guard_spec.loader.exec_module(guard)
    guard.check_host(root)
    receipt = root / "receipt.json"
    binding = {"journey": args.journey, "qualified_main": QUALIFIED_MAIN, "selected_original": controller.SELECTED}
    if args.stage == "execute":
        prior = json.loads(receipt.read_text())
        if prior.get("critical_journey_binding") != binding or prior.get("selected_original") != controller.SELECTED:
            raise RuntimeError("Changed original journey or qualified-main binding")
    sys.argv = [str(Path(controller.__file__)), args.stage]
    controller.main()
    if args.stage == "prepare":
        record = json.loads(receipt.read_text())
        record["critical_journey_binding"] = binding
        for name in EXTRA_INPUTS:
            record["source_sha256"][name] = hashlib.sha256(Path(name).read_bytes()).hexdigest()
        receipt.write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    main()
