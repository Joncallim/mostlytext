#!/usr/bin/env python3
"""Reconstruct only the inspected Foundation parser fixture from immutable owner blobs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("engine_clone", type=Path)
parser.add_argument("output", type=Path, help="New directory; existing paths are never overwritten")
args = parser.parse_args()
packet = Path(__file__).resolve().parent
manifest = json.loads((packet / "manifest.json").read_text())
revision = manifest["engine_revision"]
files = []
for record in manifest["exact_source_files"]:
    path = record["owner_path"]
    allowed = (
        path.startswith("Sources/SwiftUIMath/Internal/Syntax/")
        or path.startswith("Tests/SwiftUIMathTests/")
        or path in {
            "Sources/SwiftUIMath/Math+BodyInspection.swift",
            "Sources/SwiftUIMath/Math+ValidatedBody.swift",
            "Sources/SwiftUIMath/Internal/Helpers/BoundedRenderCache.swift",
            "Sources/SwiftUIMath/Internal/Helpers/KeyBox.swift",
            "Sources/SwiftUIMath/Internal/Helpers/Unicode.swift",
            "Sources/SwiftUIMath/Internal/Helpers/ReadWriteLockIsolated.swift",
        }
    )
    if not allowed:
        raise SystemExit(f"Uninspected file refused: {path}")
    destination = Path(record["fixture_path"])
    if destination.is_absolute() or ".." in destination.parts:
        raise SystemExit(f"Unsafe fixture path: {destination}")
    data = subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=args.engine_clone)
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise SystemExit(f"Digest mismatch: {path}")
    files.append((destination, data))
args.output.mkdir(parents=True, exist_ok=False)
for relative, data in files:
    destination = args.output / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
(args.output / "Package.swift").write_bytes((packet / "fixture-Package.swift").read_bytes())
(args.output / "Sources/SwiftUIMath/Namespace.swift").write_text("public enum Math {}\n")
(args.output / "Tests/SwiftUIMathTests/CommentContractTests.swift").write_bytes(
    (packet / "fixture-CommentContractTests.swift").read_bytes()
)
print(f"Verified and copied {len(files)} exact source/test files; Foundation fixture: {args.output}")
