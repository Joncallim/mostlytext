#!/usr/bin/env python3
"""Keep Finder-visible document/type labels in every shipped InfoPlist.strings file."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SPEC_LABEL = re.compile(r"^[ \t]*(?:-[ \t]*)?(?:CFBundleTypeName|UTTypeDescription):[ \t]*(.+?)[ \t]*$")
STRING_ENTRY = re.compile(r'^\s*"([^"\\]+)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
LOCALES = ("en", "fr", "ja", "pl")


def type_labels() -> set[str]:
    lines = (ROOT / "MacDown2/project.yml").read_text(encoding="utf-8").splitlines()
    labels = {match.group(1).strip('"\'') for line in lines if (match := SPEC_LABEL.match(line))}
    if not labels:
        raise ValueError("project.yml declares no document or exported type labels")
    return labels


def localized_labels(locale: str) -> dict[str, str]:
    path = ROOT / "MacDown2/MacDown2" / f"{locale}.lproj/InfoPlist.strings"
    entries: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("/*"):
            continue
        match = STRING_ENTRY.match(line)
        if match is None:
            raise ValueError(f"{path}: unsupported strings entry: {line}")
        key, value = match.groups()
        if key in entries:
            raise ValueError(f"{path}: duplicate label: {key}")
        entries[key] = value
    return entries


def main() -> int:
    try:
        expected = type_labels()
        for locale in LOCALES:
            observed = localized_labels(locale)
            if set(observed) != expected:
                raise ValueError(f"{locale}: missing/extra labels: {sorted(set(observed) ^ expected)}")
            if any(not value.strip() for value in observed.values()):
                raise ValueError(f"{locale}: blank Finder type label")
            if locale == "en" and any(observed[key] != key for key in expected):
                raise ValueError("en: source label differs from project.yml")
    except (OSError, ValueError) as error:
        print(json.dumps({"status": "invalid", "error": str(error)}))
        return 1
    print(json.dumps({"status": "passed", "labels": len(expected), "locales": LOCALES}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
