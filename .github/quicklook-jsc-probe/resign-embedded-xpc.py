#!/usr/bin/env python3
"""Remove Xcode test signing rights from the private fixture's embedded XPC copy."""
import os
from pathlib import Path
import plistlib
import pwd
import subprocess


EXPECTED_ENTITLEMENTS = {"com.apple.security.app-sandbox": True}
EXPECTED_ROOT = Path("/Users/runner/work/_temp/mostlytext-qljsc")
SERVICE_NAME = "QLReplyProbeXPCService.xpc"


def require_exact_entitlements(value):
    if value != EXPECTED_ENTITLEMENTS:
        raise RuntimeError("Embedded XPC service must have only the sandbox entitlement")


def entitlements_from_codesign(result):
    raw = result.stdout if b"<?xml" in result.stdout else result.stderr
    if b"<?xml" not in raw:
        raise RuntimeError("Missing signed XPC service entitlement XML")
    return plistlib.loads(raw[raw.index(b"<?xml"):])


def require_hosted_fixture():
    root = EXPECTED_ROOT
    fixture = root / "fixture"
    build = root / "build/Build/Products/Release"
    if (os.environ.get("GITHUB_ACTIONS") != "true"
            or os.environ.get("GITHUB_REPOSITORY") != "Joncallim/mostlytext"
            or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted"
            or os.environ.get("RUNNER_OS") != "macOS"
            or os.environ.get("RUNNER_TEMP") != str(root.parent)
            or os.environ.get("SRCROOT") != str(fixture)
            or os.environ.get("TARGET_BUILD_DIR") != str(build)
            or os.environ.get("TARGET_NAME") != "QLReplyProbeContainer"
            or os.environ.get("WRAPPER_NAME") != "QLReplyProbeContainer.app"
            or os.environ.get("CONFIGURATION") != "Release"
            or os.getuid() != 501 or os.geteuid() != 501
            or pwd.getpwuid(os.getuid()).pw_name != "runner"):
        raise RuntimeError("Require exact hosted Quick Look fixture build context")
    return root, fixture, build / "QLReplyProbeContainer.app/Contents/XPCServices" / SERVICE_NAME


def main():
    root, fixture, service = require_hosted_fixture()
    source = fixture / "XPCService.entitlements"
    require_exact_entitlements(plistlib.loads(source.read_bytes()))
    if service.is_symlink() or not service.is_dir():
        raise RuntimeError("Missing exact embedded XPC service bundle")
    info = plistlib.loads((service / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != "app.mostlytext.QLReplyProbe.XPCService"
            or info.get("XPCService", {}).get("ServiceType") != "Application"):
        raise RuntimeError("Unexpected embedded XPC service identity")
    observed = subprocess.run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml",
                               str(service)], capture_output=True, check=True, timeout=30)
    (root / "xpc-service-before-resign-stdout.txt").write_bytes(observed.stdout)
    (root / "xpc-service-before-resign-stderr.txt").write_bytes(observed.stderr)
    (root / "xpc-service-before-resign-entitlements.plist").write_bytes(
        plistlib.dumps(entitlements_from_codesign(observed)))
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
                    "--entitlements", str(source), "--timestamp=none", "--generate-entitlement-der",
                    str(service)], check=True, timeout=30)
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(service)], check=True, timeout=30)
    signed = subprocess.run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml",
                             str(service)], capture_output=True, check=True, timeout=30)
    (root / "xpc-service-after-resign-stdout.txt").write_bytes(signed.stdout)
    (root / "xpc-service-after-resign-stderr.txt").write_bytes(signed.stderr)
    actual = entitlements_from_codesign(signed)
    (root / "xpc-service-after-resign-entitlements.plist").write_bytes(plistlib.dumps(actual))
    require_exact_entitlements(actual)


if __name__ == "__main__":
    main()
