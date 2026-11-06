#!/usr/bin/env python3
"""First normal-app CLI observations on the disposable hosted macOS runner only."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import plistlib
import stat
import subprocess
import sys
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    environment = os.environ
    assert environment.get("GITHUB_ACTIONS") == "true" and environment.get("RUNNER_OS") == "macOS"
    assert environment.get("GITHUB_REPOSITORY") == "Joncallim/mostlytext"
    assert Path.home() == Path("/Users/runner") and platform.machine() == "arm64"
    assert platform.mac_ver()[0].split(".")[0] == "26"
    temporary = Path(environment["RUNNER_TEMP"]).resolve(strict=True)
    app, host, output, overlay_file = (Path(a).resolve() for a in sys.argv[1:])
    assert all(p.is_relative_to(temporary) for p in [app, host, output, overlay_file])
    assert host.is_file() and not output.exists()
    overlay = json.loads(overlay_file.read_text())
    spec = importlib.util.spec_from_file_location("startup_observation", Path(__file__).with_name("prepare-native-startup-observation.py"))
    observer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(observer)
    observer.verify(Path.cwd(), overlay)
    changed = set(subprocess.check_output(["git", "diff", "--name-only", "HEAD"], text=True).splitlines())
    assert changed == set(overlay["files"]), "Refuse an unrecorded source overlay"
    metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identity = metadata["CFBundleIdentifier"]
    assert identity == "app.mostlytext.MostlyText"
    executable = app / "Contents/MacOS" / metadata["CFBundleExecutable"]
    helper = app / "Contents/MacOS/mostlytext-cli"
    assert helper.is_file() and executable.is_file()
    output.mkdir()
    bin_directory = output / "bin"
    bin_directory.mkdir()
    public = bin_directory / "mostlytext"
    public.symlink_to(helper)
    source = output / "space Unicode-🙂-[fixture].md"
    source.write_bytes(b"# Native CLI fixture\r\n\r\nUntouched source.\r\n")
    source_digest = digest(source)
    receipt = {"source_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "app_sha256": digest(executable), "helper_sha256": digest(helper),
               "public_symlink": str(public), "resolved_helper": str(public.resolve()),
               "source_file_sha256": source_digest, "commands": [], "applications": [], "errors": [],
               "scope": "Derived startup observation build; no production-source, signed, installed-state or owner acceptance",
               "source_overlay": overlay}
    tracked = subprocess.check_output(["git", "ls-files", "--", "MacDown2", ".github/scripts/native-cli-app-host.swift",
                                      ".github/scripts/run-native-cli-probe.py", ".github/workflows/native-cli-probe.yml",
                                      ".github/scripts/prepare-native-startup-observation.py",
                                      ".github/scripts/test-native-startup-observation.py",
                                      ".github/scripts/run-owned-app-tests.py"], text=True).splitlines()
    receipt["source_sha256"] = {p: digest(Path(p)) for p in tracked}
    receipt["canonical_source_sha256"] = dict(receipt["source_sha256"])
    for name, item in overlay["files"].items():
        assert receipt["source_sha256"][name] == item["executed_sha256"]
        receipt["canonical_source_sha256"][name] = item["canonical_sha256"]
    receipt["pins"] = json.loads(Path("MacDown2/Packages/MacDownKit/Package.resolved").read_text())["pins"]
    current = None
    wait_process = None
    successes = {}
    current_root_was_absent = not (Path.home() / "Library/Application Support/MostlyText").exists()

    def storage_snapshot(label):
        support = Path.home() / "Library/Application Support"
        roots = [support / "MostlyText", support / "MacDown 2", support / (identity + "-editor-import-v1")]
        records, retained = [], 0

        def visit(path, depth=0, parent=None):
            nonlocal retained
            if len(records) >= 256 or depth > 8:
                return
            try:
                entry = os.stat(path if parent is None else path.name, dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                records.append({"path": str(path), "absent": True})
                return
            row = {"path": str(path), "uid": entry.st_uid, "mode": oct(entry.st_mode), "bytes": entry.st_size}
            records.append(row)
            if stat.S_ISDIR(entry.st_mode):
                directory = os.open(path if parent is None else path.name,
                                    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                try:
                    opened = os.fstat(directory)
                    assert (opened.st_dev, opened.st_ino) == (entry.st_dev, entry.st_ino)
                    for name in sorted(os.listdir(directory)):
                        visit(path / name, depth + 1, directory)
                finally:
                    os.close(directory)
            elif (current_root_was_absent and label != "before-launch" and stat.S_ISREG(entry.st_mode)
                  and path.is_relative_to(roots[0]) and path.suffix == ".json"
                  and entry.st_size <= 1024 * 1024 and retained < 16):
                # Only this newly launched first-party installation's bounded migration/session JSON.
                descriptor = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
                try:
                    opened = os.fstat(descriptor)
                    assert (opened.st_dev, opened.st_ino, opened.st_size) == (entry.st_dev, entry.st_ino, entry.st_size)
                    chunks, total = [], 0
                    while total <= 1024 * 1024:
                        chunk = os.read(descriptor, min(65536, 1024 * 1024 + 1 - total))
                        if not chunk:
                            break
                        chunks.append(chunk)
                        total += len(chunk)
                    assert total <= 1024 * 1024
                finally:
                    os.close(descriptor)
                retained += 1
                destination = output / (label + "-record-" + str(retained) + ".json")
                destination.write_bytes(b"".join(chunks))
                row["retained_as"] = destination.name

        for root in roots:
            visit(root)
        (output / (label + "-storage.json")).write_text(json.dumps(records, indent=2) + "\n")

    def persist():
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    def command(label, arguments, data=None):
        began = time.monotonic()
        try:
            result = subprocess.run([str(a) for a in arguments], input=data, capture_output=True, timeout=20)
            code, stdout, stderr, timed_out = result.returncode, result.stdout, result.stderr, False
        except subprocess.TimeoutExpired as error:
            code, stdout, stderr, timed_out = 124, error.stdout or b"", error.stderr or b"", True
        row = {"label": label, "command": [str(a) for a in arguments], "returncode": code,
               "stdout": stdout.decode("utf-8", errors="replace"), "timed_out": timed_out,
               "stderr": stderr.decode("utf-8", errors="replace"), "elapsed_seconds": time.monotonic() - began}
        receipt["commands"].append(row)
        persist()
        return row

    def app_action(operation, record=None):
        arguments = [host, operation, app]
        if record is not None:
            arguments += [str(record["pid"]), str(record["birth"])]
        row = command("app-" + operation, arguments)
        assert row["returncode"] == 0, row
        result = json.loads(row["stdout"])
        receipt["applications"].append(result)
        persist()
        return result

    def wait_for_endpoint():
        runtime = Path(subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()).resolve()
        endpoint = runtime / ("mt-" + hashlib.sha256(identity.encode()).hexdigest()[:24]) / "s"
        deadline = time.monotonic() + 10
        while not endpoint.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        return endpoint.exists()

    def observe_refusal(label, application):
        try:
            inspection = app_action("inspect", application)
            (output / (label + "-windows.json")).write_text(json.dumps(inspection, indent=2) + "\n")
            command(label + "-sample", ["sample", str(application["pid"]), "1", "-file", output / (label + ".sample.txt")])
            logs = command(label + "-unified-log", ["log", "show", "--style", "json", "--last", "1m",
                                                    "--predicate", "processIdentifier == " + str(application["pid"])])
            (output / (label + "-unified-log.json")).write_text(logs["stdout"][:1024 * 1024])
            storage_snapshot(label)
        except Exception as error:
            receipt.setdefault("observation_errors", []).append({"phase": label, "error": str(error)})
            persist()

    key = "com.joncallim.macdown2.hasCompletedFirstRun"
    try:
        before = command("first-run-key-before", ["defaults", "read", identity, key])
        assert before["returncode"] != 0, "Runner is not a fresh first-run domain"
        storage_snapshot("before-launch")
        current = app_action("launch")
        receipt["first_run_endpoint_observed"] = wait_for_endpoint()
        first = command("fresh-warm-file", [public, source])
        successes["fresh_warm_file"] = first["returncode"] == 0
        if not successes["fresh_warm_file"]:
            observe_refusal("fresh-refusal", current)
        app_action("terminate", current)
        current = None
        configured = command("configure-existing-first-run-key", ["defaults", "write", identity, key, "-bool", "true"])
        assert configured["returncode"] == 0
        command("first-run-key-after-configuration", ["defaults", "read", identity, key])
        current = app_action("launch")
        ready = wait_for_endpoint()
        if not ready:
            observe_refusal("configured-refusal", current)
        assert ready, "Configured installation did not start its actual endpoint"
        successes["configured_warm_file"] = command("configured-warm-file", [public, source])["returncode"] == 0
        successes["missing_file_rejected"] = command("missing-file", [public, output / "does-not-exist.md"])["returncode"] == 4
        wait_process = subprocess.Popen([str(public), "--wait", str(source)], stdin=subprocess.DEVNULL,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.5)
        assert wait_process.poll() is None, "--wait returned before the real clean app closed"
        app_action("terminate", current)
        current = None
        stdout, stderr = wait_process.communicate(timeout=20)
        row = {"label": "wait-completes-after-normal-app-termination", "returncode": wait_process.returncode,
               "stdout": stdout.decode("utf-8", errors="replace"), "stderr": stderr.decode("utf-8", errors="replace")}
        receipt["commands"].append(row)
        successes["wait_completed_after_normal_quit"] = wait_process.returncode == 0
        wait_process = None
        current = app_action("launch")
        assert wait_for_endpoint()
        stdin = "# Piped Markdown\r\n\r\nUnicode 🙂 e\u0301\r\n".encode()
        (output / "stdin-source.md").write_bytes(stdin)
        receipt["stdin_sha256"] = hashlib.sha256(stdin).hexdigest()
        successes["configured_stdin_acknowledged"] = command("configured-implicit-stdin", [public], stdin)["returncode"] == 0
        successes["invalid_utf8_rejected"] = command("invalid-utf8-stdin", [public], b"\xff")["returncode"] == 3
        assert digest(source) == source_digest and digest(executable) == receipt["app_sha256"]
        assert digest(helper) == receipt["helper_sha256"]
    except Exception as error:
        receipt["errors"].append(str(error))
    finally:
        if wait_process is not None and wait_process.poll() is None:
            wait_process.terminate()
            try:
                wait_process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                wait_process.kill()
                wait_process.communicate(timeout=10)
                receipt["errors"].append("Owned CLI wait process needed forced fixture cleanup")
        if current is not None:
            try:
                app_action("cleanup", current)
            except Exception as error:
                receipt["errors"].append("Identity-bound fixture cleanup: " + str(error))
        receipt["criteria"] = successes
        receipt["passed"] = len(successes) == 6 and all(successes.values()) and not receipt["errors"]
        persist()
    print(json.dumps({k: receipt[k] for k in ["source_head", "criteria", "errors", "passed", "scope"]}), flush=True)
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
