#!/usr/bin/env python3
"""Run an owned native test command with bounded, exact-app stack diagnostics."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def owned_apps(executable, started):
    environment = dict(os.environ, LC_ALL="C")
    rows = subprocess.check_output(["ps", "-axo", "pid=,uid=,comm="], env=environment, text=True).splitlines()
    records = []
    for row in rows:
        fields = row.strip().split(None, 2)
        if len(fields) != 3 or fields[1] != str(os.getuid()) or fields[2] != str(executable):
            continue
        pid = int(fields[0])
        try:
            birth = subprocess.check_output(["ps", "-p", str(pid), "-o", "lstart="], env=environment, text=True).strip()
        except subprocess.CalledProcessError:
            continue
        try:
            timestamp = time.mktime(datetime.datetime.strptime(birth, "%a %b %d %H:%M:%S %Y").timetuple())
        except ValueError:
            continue
        if timestamp >= started - 1:
            records.append({"pid": pid, "birth": birth, "executable": str(executable)})
    return records


def sample_apps(executable, started, output, ordinal):
    samples = []
    for record in owned_apps(executable, started):
        raw = output / ("app-%s-%s.raw" % (record["pid"], ordinal))
        log = output / ("sample-%s-%s.log" % (record["pid"], ordinal))
        # Check the exact app path, uid and process birth again at the action edge.
        if record not in owned_apps(executable, started):
            continue
        with log.open("w") as diagnostics:
            try:
                result = subprocess.run(["sample", str(record["pid"]), "2", "-file", str(raw)],
                                        stdout=diagnostics, stderr=subprocess.STDOUT, timeout=10)
                record["sample_status"] = result.returncode
            except subprocess.TimeoutExpired:
                record["sample_status"] = "sample-tool-timeout"
        if raw.exists():
            record["sample_bytes"] = raw.stat().st_size
            record["sample_sha256"] = hashlib.sha256(raw.read_bytes()).hexdigest()
            if raw.stat().st_size <= 1024 * 1024:
                destination = raw.with_suffix(".sample.txt")
                shutil.copyfile(raw, destination)
                record["sample_file"] = destination.name
            else:
                record["sample_omitted"] = "exceeds 1 MiB artifact limit"
        samples.append(record)
    return samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("executable", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not args.executable.is_absolute() or not args.executable.is_file():
        parser.error("An exact built test app and a test command are required")
    args.output.mkdir(parents=True, exist_ok=False)
    started = time.time()
    began = time.monotonic()
    process = subprocess.Popen(command, start_new_session=True)
    cancelled = False

    def cancel(_signal, _frame):
        nonlocal cancelled
        cancelled = True

    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    identity = {"pid": process.pid, "started": started, "command": command,
                "app": str(args.executable), "app_sha256": hashlib.sha256(args.executable.read_bytes()).hexdigest(),
                "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()}
    (args.output / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
    samples = []
    pending_samples = [120, 240]
    timed_out = False
    while process.poll() is None:
        elapsed = time.monotonic() - began
        if pending_samples and elapsed >= pending_samples[0]:
            ordinal = pending_samples.pop(0)
            try:
                samples.extend(sample_apps(args.executable, started, args.output, ordinal))
            except (OSError, subprocess.SubprocessError) as error:
                samples.append({"diagnostic_error": str(error), "elapsed_seconds": elapsed})
            (args.output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
            print("Owned native diagnostics: elapsed=%ss samples=%s" % (int(elapsed), len(samples)), flush=True)
        if cancelled or elapsed >= 600:
            timed_out = not cancelled
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            break
        time.sleep(1)
    cleanup = []
    if timed_out or cancelled:
        for record in owned_apps(args.executable, started):
            if record in owned_apps(args.executable, started):
                try:
                    os.kill(record["pid"], signal.SIGTERM)
                    cleanup.append(record)
                except ProcessLookupError:
                    pass
    status = {"returncode": process.returncode, "timed_out": timed_out, "cancelled": cancelled,
              "elapsed_seconds": time.monotonic() - began, "app_cleanup_requested": cleanup}
    (args.output / "status.json").write_text(json.dumps(status, indent=2) + "\n")
    (args.output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    print("Owned native command status: " + json.dumps(status), flush=True)
    if cancelled:
        raise SystemExit(130)
    if timed_out:
        raise SystemExit(124)
    raise SystemExit(process.returncode if process.returncode >= 0 else 128 - process.returncode)


if __name__ == "__main__":
    main()
