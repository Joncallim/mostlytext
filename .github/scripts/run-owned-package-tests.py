#!/usr/bin/env python3
"""Run one owned Swift Testing host and retain only its fresh crash reports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time

# The normal hosted package corpus completes well before these external stops.
# Sample a late helper at 20 minutes; fail and retire only that child at 30.
# This does not change any Swift Testing or renderer deadline.
SAMPLE_AT_SECONDS = 1200
MAX_RUN_SECONDS = 1800
SAMPLE_FILE_LIMIT = 2 * 1024 * 1024
SAMPLE_LOG_LIMIT = 64 * 1024


def collect_reports(directory, destination, pid, executable, started):
    records = []
    total = 0
    decoder = json.JSONDecoder()
    candidates = sorted(directory.glob("*.ips")) if directory.is_dir() else []
    for report in candidates:
        metadata = report.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_mtime < started:
            continue
        if metadata.st_size > 1024 * 1024 or total + metadata.st_size > 8 * 1024 * 1024:
            continue
        descriptor = os.open(report, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as source:
            current = os.fstat(source.fileno())
            if (current.st_dev, current.st_ino) != (metadata.st_dev, metadata.st_ino):
                continue
            raw = source.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024 or total + len(raw) > 8 * 1024 * 1024:
            continue
        try:
            text = raw.decode("utf-8").lstrip()
            _, end = decoder.raw_decode(text)
            body, _ = decoder.raw_decode(text[end:].lstrip())
        except (UnicodeDecodeError, ValueError):
            continue
        if not isinstance(body, dict) or body.get("pid") != pid or Path(body.get("procPath", "")).name != executable:
            continue
        destination.mkdir(parents=True, exist_ok=True)
        (destination / report.name).write_bytes(raw)
        total += len(raw)
        records.append({"name": report.name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
    return records


def live_host_identity(process, host):
    # Popen owns the unreaped child PID. Check its user and executable again
    # before asking sample to attach to that process.
    if process.poll() is not None:
        return None
    try:
        line = subprocess.check_output(
            ["ps", "-p", str(process.pid), "-o", "uid=", "-o", "comm="],
            text=True, timeout=5,
        ).strip()
    except (OSError, subprocess.SubprocessError):
        return None
    fields = line.split(None, 1)
    if len(fields) != 2 or fields[0] != str(os.getuid()) or fields[1] != str(host):
        return None
    # Do not poll a second time: reaping a just-exited child here would allow
    # its PID to be reused before sample attaches.
    return {"pid": process.pid, "uid": os.getuid(), "executable": str(host)}


def sample_host(process, host, output, label):
    record = {"phase": label, "pid": process.pid}
    identity = live_host_identity(process, host)
    if identity is None:
        record["sample_refused"] = "owned helper identity unavailable"
        return record
    record.update(identity)
    raw = output / (label + ".sample.raw")
    diagnostic = output / (label + ".sample.log")
    with diagnostic.open("w") as log:
        try:
            completed = subprocess.run(
                ["sample", str(process.pid), "2", "-file", str(raw)],
                stdout=log, stderr=subprocess.STDOUT, timeout=10,
            )
            record["sample_returncode"] = completed.returncode
        except (OSError, subprocess.TimeoutExpired) as error:
            record["sample_error"] = type(error).__name__
    with diagnostic.open("r+b") as log:
        original_bytes = log.seek(0, os.SEEK_END)
        if original_bytes > SAMPLE_LOG_LIMIT:
            log.truncate(SAMPLE_LOG_LIMIT)
    record["sample_log_original_bytes"] = original_bytes
    record["sample_log_bytes"] = min(original_bytes, SAMPLE_LOG_LIMIT)
    record["sample_log_truncated"] = original_bytes > SAMPLE_LOG_LIMIT
    record["sample_log_sha256"] = hashlib.sha256(diagnostic.read_bytes()).hexdigest()
    if raw.is_file():
        size = raw.stat().st_size
        record["sample_bytes"] = size
        if size <= SAMPLE_FILE_LIMIT:
            record["sample_sha256"] = hashlib.sha256(raw.read_bytes()).hexdigest()
            retained = raw.with_suffix(".txt")
            raw.rename(retained)
            record["sample_file"] = retained.name
        else:
            raw.unlink()
            record["sample_omitted"] = "exceeds 2 MiB artifact limit"
    return record


def wait_bounded(process, host, output):
    began = time.monotonic()
    samples = []
    for deadline, label in ((SAMPLE_AT_SECONDS, "late"), (MAX_RUN_SECONDS, "timeout")):
        remaining = max(0, deadline - (time.monotonic() - began))
        try:
            process.wait(timeout=remaining)
            return False, samples
        except subprocess.TimeoutExpired:
            samples.append(sample_host(process, host, output, label))
            (output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                samples.append({"phase": "termination", "cleanup_unconfirmed": True})
                (output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    return True, samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("host", type=Path)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    started = time.time()
    began = time.monotonic()
    process = subprocess.Popen([str(args.host), *args.arguments])
    identity = {"pid": process.pid, "host": str(args.host), "started": started,
                "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "host_sha256": hashlib.sha256(args.host.read_bytes()).hexdigest()}
    (args.output / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
    timed_out, samples = wait_bounded(process, args.host, args.output)
    result = process.returncode
    # Existing evidence verifiers compare status.json to this exact shape.
    (args.output / "status.json").write_text(json.dumps({"returncode": result}) + "\n")
    (args.output / "watchdog.json").write_text(json.dumps({
        "timed_out": timed_out,
        "elapsed_seconds": round(time.monotonic() - began, 3),
        "cleanup_confirmed": result is not None,
        "sample_phases": [record["phase"] for record in samples],
    }, indent=2) + "\n")
    reports = []
    if result != 0:
        time.sleep(5)  # Let macOS finish writing this process's crash report.
        try:
            reports = collect_reports(Path.home() / "Library/Logs/DiagnosticReports", args.output / "crashes",
                                      process.pid, args.host.name, started)
        except OSError as error:
            (args.output / "collection-error.txt").write_text(str(error) + "\n")
    (args.output / "reports.json").write_text(json.dumps(reports, indent=2) + "\n")
    if timed_out:
        raise SystemExit(124)
    raise SystemExit(result if result >= 0 else 128 - result)


if __name__ == "__main__":
    main()
