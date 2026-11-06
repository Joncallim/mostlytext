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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("host", type=Path)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    started = time.time()
    process = subprocess.Popen([str(args.host), *args.arguments])
    identity = {"pid": process.pid, "host": str(args.host), "started": started,
                "checkout": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "host_sha256": hashlib.sha256(args.host.read_bytes()).hexdigest()}
    (args.output / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
    result = process.wait()
    (args.output / "status.json").write_text(json.dumps({"returncode": result}) + "\n")
    reports = []
    if result != 0:
        time.sleep(5)  # Let macOS finish writing this process's crash report.
        try:
            reports = collect_reports(Path.home() / "Library/Logs/DiagnosticReports", args.output / "crashes",
                                      process.pid, args.host.name, started)
        except OSError as error:
            (args.output / "collection-error.txt").write_text(str(error) + "\n")
    (args.output / "reports.json").write_text(json.dumps(reports, indent=2) + "\n")
    raise SystemExit(result if result >= 0 else 128 - result)


if __name__ == "__main__":
    main()
