#!/usr/bin/env python3
"""Guard a bounded set of plain-String UI and error sinks.

This is a source review aid, not a Swift parser or the final E16 string audit.
It scans every first-party production Swift input, then records exact literal
routes at selected AppKit, filename, accessibility, and error sinks. Compiler
extraction remains the separate positive catalog-coverage check.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


ROOTS = (
    "MacDown2/MacDown2",
    "MacDown2/MacDown2CLI",
    "MacDown2/Packages/MacDownKit/Sources",
)
SINKS = (
    ("appkit_property", re.compile(
        r"\b(?:window|panel|alert)\.(?:title|message|messageText|informativeText|prompt|toolTip|placeholderString)\s*=")),
    ("appkit_button", re.compile(r"\b(?:addButton|addCloseButton)\s*\(\s*withTitle\s*:")),
    ("appkit_constructor", re.compile(r"\b(?:NSMenuItem|NSButton)\s*\(\s*title\s*:")),
    ("appkit_accessibility", re.compile(r"\bsetAccessibility(?:Label|Help|Value)\s*\(")),
    ("filename_fallback", re.compile(r"\b(?:baseTitle|baseName|defaultName|exportName)\s*=")),
    ("folder_error", re.compile(r"FileTreeOperationError\.underlying\s*\(")),
    ("replace_error", re.compile(r"\.failed\s*\(")),
    ("workspace_save_name", re.compile(r"\bstatic\s+func\s+defaultSaveAsName\b")),
    ("theme_export_name", re.compile(r"\breturn\s+result\.isEmpty\s*\?")),
)
LITERAL = re.compile(r'""".*?"""|"(?:\\.|[^"\\])*"', re.S)
LOCALIZED = re.compile(r"\bString\s*\(\s*localized\s*:", re.S)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sources(repo: Path) -> list[Path]:
    return sorted(path for root in ROOTS for path in (repo / root).rglob("*.swift")
                  if "Resources" not in path.relative_to(repo / root).parts)


def scan(repo: Path) -> tuple[list[dict], dict[str, str], int]:
    sites: list[dict] = []
    file_hashes: dict[str, str] = {}
    files = sources(repo)
    for source in files:
        relative = source.relative_to(repo).as_posix()
        lines = source.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if line.lstrip().startswith("//"):
                continue
            for kind, pattern in SINKS:
                if kind == "replace_error" and not relative.endswith("TextSearch/WorkspaceReplaceEngine.swift"):
                    continue
                if kind == "workspace_save_name" and not relative.endswith("Workspace/WorkspaceModel+Saving.swift"):
                    continue
                if kind == "theme_export_name" and not relative.endswith("MacDown2/ThemeExportDocument.swift"):
                    continue
                match = pattern.search(line)
                if not match:
                    continue
                # The selected sink is followed by a literal on this line or
                # in a short, indented String(localized:) continuation.
                tail = line[match.end():]
                if kind != "workspace_save_name" and LITERAL.search(tail) is None and tail.strip() and not tail.strip().endswith(("(", ":")):
                    continue
                segment = tail + "\n" + "\n".join(lines[index + 1:index + 13])
                literal = LITERAL.search(segment)
                if literal is None:
                    continue
                prefix = segment[:literal.start()]
                # Stop before a later statement's literal. This checker does
                # not attempt arbitrary interprocedural Swift dataflow.
                if ";" in prefix or "return " in prefix:
                    continue
                sites.append({
                    "path": relative,
                    "line": index + 1,
                    "kind": kind,
                    "literal": literal.group(),
                    "route": "localized" if LOCALIZED.search(prefix) else "plain",
                })
                file_hashes[relative] = digest(source.read_bytes())
    return sorted(sites, key=lambda row: (row["path"], row["line"], row["kind"])), file_hashes, len(files)


def check(repo: Path, ledger: Path) -> dict:
    recorded = json.loads(ledger.read_text(encoding="utf-8"))
    if recorded.get("schema") != 1 or recorded.get("scope") != "selected_plain_string_sinks":
        raise ValueError("unsupported sink ledger")
    sites, hashes, count = scan(repo)
    expected = recorded.get("sites")
    if type(expected) is not list or type(recorded.get("source_sha256")) is not dict:
        raise ValueError("malformed sink ledger")
    for site in expected:
        if site.get("route") == "plain" and not site.get("reason"):
            raise ValueError(f"unreviewed plain String: {site}")
    observed = [{**site, **({"reason": row["reason"]} if "reason" in row else {})}
                for site in sites for row in expected
                if all(site[key] == row.get(key) for key in ("path", "line", "kind", "literal", "route"))]
    if len(observed) != len(sites) or observed != expected:
        raise ValueError("selected UI/error sink routes changed; inspect --discover and update the reviewed ledger")
    if hashes != recorded["source_sha256"]:
        raise ValueError("reviewed sink source bytes changed; re-audit before updating hashes")
    deferred = recorded.get("deferred_review", [])
    if type(deferred) is not list:
        raise ValueError("malformed deferred review list")
    for row in deferred:
        if row.get("status") != "open" or not row.get("reason"):
            raise ValueError(f"malformed deferred review: {row}")
        if not (repo / row["path"]).is_file():
            raise ValueError(f"missing deferred source: {row['path']}")
    return {"status": "passed", "production_swift_inputs": count,
            "selected_sinks": len(sites), "plain_exceptions": sum(site["route"] == "plain" for site in sites),
            "deferred_review": len(deferred)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--ledger", type=Path, default=Path(__file__).resolve().parents[1] /
                        "plain-string-sink-ledger-2026-11-09.json")
    parser.add_argument("--discover", action="store_true", help="print candidates; do not accept them")
    args = parser.parse_args()
    try:
        if args.discover:
            sites, hashes, count = scan(args.repo.resolve())
            print(json.dumps({"production_swift_inputs": count, "sites": sites,
                              "source_sha256": hashes}, ensure_ascii=False, indent=2))
        else:
            print(json.dumps(check(args.repo.resolve(), args.ledger)))
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps({"status": "invalid", "error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
