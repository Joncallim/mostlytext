#!/usr/bin/env python3
"""Run only two private harmless SwiftUI controls on a disposable hosted Mac."""
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import pwd
import subprocess
import sys


def main():
    if sys.flags.optimize:
        raise RuntimeError("Optimized Python is refused before native preparation")
    account = pwd.getpwuid(os.getuid())
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    if not (os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("GITHUB_REPOSITORY") == "Joncallim/mostlytext"
            and platform.system() == "Darwin" and platform.machine() == "arm64" and platform.mac_ver()[0].split(".")[0] == "26"
            and os.getuid() == os.geteuid() != 0 and account.pw_name == "runner" and account.pw_dir == "/Users/runner"
            and Path.home() == Path("/Users/runner")):
        raise RuntimeError("A disposable hosted runner is required")
    if event.get("pull_request", {}).get("head", {}).get("repo", {}).get("full_name") != "Joncallim/mostlytext":
        raise RuntimeError("A same-repository reviewed head is required")
    root = Path(os.environ["RUNNER_TEMP"]).resolve() / "mostlytext-scene"
    if root.exists():
        raise RuntimeError("Refuse an existing control directory")
    root.mkdir(mode=0o700)
    inputs = [".github/startup-scene-probe/Probe.swift", ".github/scripts/run-startup-scene-probe.py", ".github/workflows/startup-scene-probe.yml"]
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    receipt = {"checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "inputs": {p: sha(Path(p)) for p in inputs}, "commands": [], "results": {}, "scope": "Standalone structural controls only"}
    def save(): (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    def command(label, args, timeout):
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        receipt["commands"].append({"label": label, "args": [str(a) for a in args], "returncode": p.returncode,
                                    "stdout": p.stdout[:65536], "stderr": p.stderr[:65536]})
        save()
        if p.returncode: raise RuntimeError(label + " failed")
    save()
    for variant in ["former", "observed"]:
        app = root / (variant + ".app")
        binary = app / "Contents/MacOS/Probe"
        binary.parent.mkdir(parents=True)
        info = {"CFBundleIdentifier": "app.mostlytext.StartupScene." + variant, "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
                "CFBundleName": "Standalone scene control", "LSMinimumSystemVersion": "26.0", "NSPrincipalClass": "NSApplication"}
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        args = ["swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete", "-O"]
        if variant == "observed": args += ["-D", "OBSERVED_SCENE"]
        command(variant + "-compile", args + [inputs[0], "-o", str(binary)], 120)
        command(variant + "-sign", ["codesign", "--force", "--sign", "-", str(app)], 30)
        command(variant + "-run", [str(binary), str(root / (variant + ".json"))], 20)
        result = json.loads((root / (variant + ".json")).read_text())
        if result["ready"] is not True or not result["samples"] or "SCENE_READY_CONTROL" in result["before"]:
            raise RuntimeError("Invalid delayed-readiness control")
        receipt["results"][variant] = result
        receipt.setdefault("binaries", {})[variant] = sha(binary)
        save()
    # Preserve both observations even if the hypothesized causal difference is refuted.
    receipt["causal_difference_proved"] = (receipt["results"]["former"]["marker_seen"] is False
                                             and receipt["results"]["observed"]["marker_seen"] is True)
    for p, digest in receipt["inputs"].items():
        if sha(Path(p)) != digest: raise RuntimeError("Changed source")
    save()
    if not receipt["causal_difference_proved"]:
        raise RuntimeError("Startup-observation hypothesis refuted by actual controls")


if __name__ == "__main__":
    main()
