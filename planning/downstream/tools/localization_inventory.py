#!/usr/bin/env python3
"""Inventory and structurally validate the repository's XCStrings catalogs.

This is deliberately a static, hermetic audit aid.  It reports only evidence
available in the checkout: catalog structure, package resource declarations,
and direct literal call sites.  It does not extract strings, compile catalogs,
choose plural forms, assess translation quality, or claim native review.
"""

from __future__ import annotations

import argparse
import configparser
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


SCHEMA = 1


def catalog_paths(repo: Path) -> list[Path]:
    """Read source catalogs, excluding local build products."""
    return sorted(path for path in repo.glob("MacDown2/**/*.xcstrings") if ".build" not in path.parts)
PRINTF = re.compile(r"%(?:(?P<position>\d+)\$)?(?P<type>@|lld|ld|d|f|g|s|u|zu|llu|lf)")
SUBSTITUTION = re.compile(r"%#@(?P<name>[A-Za-z_]\w*)@")
VARIANT_REFERENCE = re.compile(r"%(?P<name>[A-Za-z_][A-Za-z0-9_]*)")
DIRECT_CALL = re.compile(r"(?:String|AttributedString)\s*\(\s*localized:\s*\"(?P<key>(?:\\.|[^\"\\])*)\"", re.S)


class CatalogError(ValueError):
    """A catalog cannot provide reliable structural evidence."""


def repo_relative(repo: Path, path: Path) -> str:
    return path.relative_to(repo).as_posix()


def load_catalog(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CatalogError(f"{path}: malformed JSON: {error}") from error
    if not isinstance(value, dict) or not isinstance(value.get("strings"), dict):
        raise CatalogError(f"{path}: expected an object with a strings object")
    if not isinstance(value.get("sourceLanguage"), str) or not value["sourceLanguage"].strip():
        raise CatalogError(f"{path}: expected a nonempty sourceLanguage")
    for key, entry in value["strings"].items():
        if not isinstance(entry, dict):
            raise CatalogError(f"{path}: {key!r} is not a string entry")
        if "comment" in entry and not isinstance(entry["comment"], str):
            raise CatalogError(f"{path}: {key!r} comment is not a string")
        localizations = entry.get("localizations", {})
        if not isinstance(localizations, dict):
            raise CatalogError(f"{path}: {key!r} localizations is not an object")
        for locale, localization in localizations.items():
            if not isinstance(localization, dict):
                raise CatalogError(f"{path}: {key!r}:{locale}: localization is not an object")
            unit = localization.get("stringUnit")
            if unit is not None and not isinstance(unit, dict):
                raise CatalogError(f"{path}: {key!r}:{locale}: stringUnit is not an object")
            if isinstance(unit, dict) and "value" in unit and not isinstance(unit["value"], str):
                raise CatalogError(f"{path}: {key!r}:{locale}: stringUnit.value is not a string")
            variations = localization.get("variations", {})
            if not isinstance(variations, dict):
                raise CatalogError(f"{path}: {key!r}:{locale}: variations is not an object")
            plural = variations.get("plural", {})
            if not isinstance(plural, dict):
                raise CatalogError(f"{path}: {key!r}:{locale}: plural variations is not an object")
            for category, variant in plural.items():
                if not isinstance(variant, dict):
                    raise CatalogError(f"{path}: {key!r}:{locale}: plural {category!r} is not an object")
                variant_unit = variant.get("stringUnit")
                if "stringUnit" in variant and not isinstance(variant_unit, dict):
                    raise CatalogError(f"{path}: {key!r}:{locale}: plural {category!r} stringUnit is not an object")
                if isinstance(variant_unit, dict) and "value" in variant_unit and not isinstance(variant_unit["value"], str):
                    raise CatalogError(f"{path}: {key!r}:{locale}: plural {category!r} stringUnit.value is not a string")
            substitutions = localization.get("substitutions", {})
            if not isinstance(substitutions, dict):
                raise CatalogError(f"{path}: {key!r}:{locale}: substitutions is not an object")
            for name, substitution in substitutions.items():
                if not isinstance(substitution, dict):
                    raise CatalogError(f"{path}: {key!r}:{locale}: substitution {name!r} is not an object")
                arg_num = substitution.get("argNum")
                if type(arg_num) is not int or arg_num < 1:
                    raise CatalogError(f"{path}: {key!r}:{locale}: substitution {name!r} argNum must be a positive integer")
                if not isinstance(substitution.get("formatSpecifier"), str):
                    raise CatalogError(f"{path}: {key!r}:{locale}: substitution {name!r} formatSpecifier is not a string")
                variations = substitution.get("variations", {})
                if not isinstance(variations, dict):
                    raise CatalogError(f"{path}: {key!r}:{locale}: substitution {name!r} variations is not an object")
                plural = variations.get("plural", {})
                if not isinstance(plural, dict):
                    raise CatalogError(f"{path}: {key!r}:{locale}: substitution {name!r} plural variations is not an object")
                for category, variant in plural.items():
                    if not isinstance(variant, dict):
                        raise CatalogError(f"{path}: {key!r}:{locale}: plural {name!r}/{category!r} is not an object")
    return value


def printf_signature(value: str) -> list[dict[str, Any]]:
    """Return canonical printf argument position/type evidence; ignore escaped %%."""
    signature: list[dict[str, Any]] = []
    index = 0
    next_position = 1
    while index < len(value):
        if value[index:index + 2] == "%%":
            index += 2
            continue
        match = PRINTF.match(value, index)
        if match:
            position = int(match.group("position")) if match.group("position") else next_position
            if position < 1:
                raise CatalogError("printf argument positions are 1-based; %0$ is invalid")
            if match.group("position") is None:
                next_position += 1
            signature.append({"position": position, "type": match.group("type")})
            index = match.end()
        else:
            index += 1
    return sorted(signature, key=lambda argument: (argument["position"], argument["type"]))


def catalog_target(repo: Path, catalog: Path) -> tuple[str, str, Path | None]:
    relative = repo_relative(repo, catalog)
    if relative == "MacDown2/MacDown2/Localizable.xcstrings":
        return "MacDown2", "Bundle.main (project target resource)", repo / "MacDown2/MacDown2"
    parts = catalog.parts
    try:
        source_index = parts.index("Sources")
        target = parts[source_index + 1]
    except (ValueError, IndexError):
        return "unknown", "unknown (path is not a known app/package resource)", None
    manifest = repo / "MacDown2/Packages/MacDownKit/Package.swift"
    declaration = manifest.read_text(encoding="utf-8") if manifest.exists() else ""
    resource_pattern = re.compile(r"\.target\(\s*name:\s*\"" + re.escape(target) + r"\"[\s\S]{0,1000}?resources:\s*\[\.process\(\"Resources\"\)\]")
    bundle = "Bundle.module (SwiftPM processed resource)" if resource_pattern.search(declaration) else "unknown (no matching SwiftPM resource declaration)"
    return target, bundle, catalog.parents[1]


def index_direct_callsites(source_roots: dict[str, Path | None], repo: Path) -> dict[str, dict[str, list[str]]]:
    """Index relevant source files once, then assign literal calls to targets."""
    found: dict[str, dict[str, list[str]]] = {target: {} for target in source_roots}
    paths = sorted({repo_relative(repo, root) for root in source_roots.values() if root is not None})
    search = subprocess.run(
        ["git", "-C", str(repo), "grep", "-l", "-e", "String(localized:", "-e", "AttributedString(localized:", "--", *paths],
        capture_output=True, text=True, check=False,
    )
    if search.returncode not in (0, 1):
        raise CatalogError(f"could not index localized call sites: {search.stderr.strip()}")
    sources = [repo / path for path in search.stdout.splitlines()]
    for source in sources:
        target = next((name for name, root in source_roots.items() if root is not None and source.is_relative_to(root)), None)
        if target is None:
            continue
        text = source.read_text(encoding="utf-8")
        for match in DIRECT_CALL.finditer(text):
            # A direct literal is useful evidence. Swift interpolation is left
            # as unknown rather than being guessed from source spelling.
            literal = match.group("key")
            line = text.count("\n", 0, match.start()) + 1
            found[target].setdefault(literal, []).append(f"{repo_relative(repo, source)}:{line}")
    return found


def variants(localization: dict[str, Any]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    plural = localization.get("variations", {}).get("plural", {})
    if isinstance(plural, dict) and plural:
        result["value"] = sorted(plural)
    for name, substitution in sorted(localization.get("substitutions", {}).items()):
        variation = substitution.get("variations", {}) if isinstance(substitution, dict) else {}
        plural = variation.get("plural", {}) if isinstance(variation, dict) else {}
        if isinstance(plural, dict):
            result[name] = sorted(plural)
    return result


def localization_state(localization: dict[str, Any]) -> str:
    unit = localization.get("stringUnit")
    if isinstance(unit, dict):
        return unit.get("state", "unknown")
    plural = localization.get("variations", {}).get("plural", {})
    states = {
        variant.get("stringUnit", {}).get("state", "unknown")
        if isinstance(variant.get("stringUnit"), dict) else "unknown"
        for variant in plural.values()
    }
    return states.pop() if len(states) == 1 else "unknown"


def inventory(repo: Path) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    paths = catalog_paths(repo)
    catalogs = {path: load_catalog(path) for path in paths}
    ownership = {path: catalog_target(repo, path) for path in paths}
    source_roots = {target: source_root for target, _, source_root in ownership.values()}
    callsite_indexes = index_direct_callsites(source_roots, repo)
    for catalog_path in paths:
        catalog = catalogs[catalog_path]
        target, bundle, _ = ownership[catalog_path]
        for key, entry in sorted(catalog["strings"].items()):
            if not isinstance(entry, dict):
                raise CatalogError(f"{catalog_path}: {key!r} is not a string entry")
            localizations = entry.get("localizations", {})
            if not isinstance(localizations, dict):
                raise CatalogError(f"{catalog_path}: {key!r} localizations is not an object")
            locale_states = {
                locale: localization_state(localization)
                for locale, localization in sorted(localizations.items())
                if isinstance(localization, dict)
            }
            swift_spelling = key.replace("\\", "\\\\").replace('"', '\\"')
            callsites = callsite_indexes[target].get(swift_spelling, [])
            entries.append({
                "target": target,
                "catalog": repo_relative(repo, catalog_path),
                "bundle": bundle,
                "key": key,
                "source_default_value": key,
                "translator_comment": entry.get("comment", "unknown_no_catalog_comment"),
                "required_locales": ["fr", "ja", "pl"],
                "required_locale_evidence": "planning/downstream/issue-17-handoff.md: retain established three plural-family verification locales",
                "interpolation": {
                    "printf_argument_types": printf_signature(key),
                    "contains_inflection_markup": "(inflect:" in key,
                },
                "variants": {locale: variants(value) for locale, value in sorted(localizations.items()) if isinstance(value, dict)},
                "locale_states": locale_states,
                "callsites": callsites,
                "callsite_evidence": "direct_literal_static_match" if callsites else "unknown_or_nonliteral_static_callsite",
                "review_state": "unknown_no_native_review_record_in_checkout",
            })
    return {
        "schema": SCHEMA,
        "scope": "catalog-backed product strings only; excludes authored document text and stable engine codes by construction",
        "limitations": [
            "Static call sites include only direct String/AttributedString localized literals; nonliteral and SwiftUI extraction evidence is unknown.",
            "Translation quality, native-speaker review, runtime resolution, catalog compilation, CLDR behavior, and layout acceptance are not evaluated.",
        ],
        "entries": entries,
    }


def validate_localization(catalog_path: Path, key: str, locale: str, value: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    source_signature = printf_signature(key)
    plural = value.get("variations", {}).get("plural", {})
    if plural:
        if "other" not in plural:
            errors.append(f"{catalog_path}:{key!r}:{locale}: plural value lacks an other variant")
        for category, variant in plural.items():
            variant_value = variant.get("stringUnit", {}).get("value")
            if not isinstance(variant_value, str):
                errors.append(f"{catalog_path}:{key!r}:{locale}: plural value/{category!r} lacks a string value")
                continue
            translated_signature = printf_signature(variant_value)
            if translated_signature != source_signature:
                errors.append(f"{catalog_path}:{key!r}:{locale}: plural value/{category!r} placeholders {translated_signature} do not match source {source_signature}")
    unit = value.get("stringUnit")
    if not isinstance(unit, dict) or not isinstance(unit.get("value"), str):
        return errors  # An untranslated locale is inventory evidence, not malformed structure.
    translated = unit["value"]
    substitutions = value.get("substitutions", {})
    if not isinstance(substitutions, dict):
        return [f"{catalog_path}:{key!r}:{locale}: substitutions is not an object"]
    if substitutions:
        ordered: list[tuple[int, str, str]] = []
        for name, substitution in substitutions.items():
            if not isinstance(substitution, dict) or not isinstance(substitution.get("argNum"), int) or not isinstance(substitution.get("formatSpecifier"), str):
                errors.append(f"{catalog_path}:{key!r}:{locale}: malformed substitution {name!r}")
                continue
            ordered.append((substitution["argNum"], name, substitution["formatSpecifier"]))
            plural = substitution.get("variations", {}).get("plural", {}) if isinstance(substitution.get("variations", {}), dict) else {}
            if plural:
                if not isinstance(plural, dict) or "other" not in plural:
                    errors.append(f"{catalog_path}:{key!r}:{locale}: plural substitution {name!r} lacks an other variant")
                    continue
                for category, variant in plural.items():
                    variant_value = variant.get("stringUnit", {}).get("value") if isinstance(variant, dict) else None
                    if not isinstance(variant_value, str):
                        errors.append(f"{catalog_path}:{key!r}:{locale}: plural {name!r}/{category!r} lacks a string value")
                    else:
                        # XCStrings emits %arg for a substitution named arg1.
                        # Preserve that convention rather than assuming the catalog
                        # repeats the numeric argument suffix in every variant.
                        variant_name = re.sub(r"\d+$", "", name)
                        if variant_name not in VARIANT_REFERENCE.findall(variant_value):
                            errors.append(f"{catalog_path}:{key!r}:{locale}: plural {name!r}/{category!r} omits %{variant_name}")
        ordered.sort()
        actual_signature = [
            {"position": position, "type": specifier}
            for position, _, specifier in sorted(ordered)
        ]
        if actual_signature != source_signature:
            errors.append(f"{catalog_path}:{key!r}:{locale}: substitution types {actual_signature} do not match source {source_signature}")
        expected_refs = {name for _, name, _ in ordered}
        actual_refs = set(SUBSTITUTION.findall(translated))
        if actual_refs != expected_refs:
            errors.append(f"{catalog_path}:{key!r}:{locale}: substitution references {sorted(actual_refs)} do not match {sorted(expected_refs)}")
    else:
        translated_signature = printf_signature(translated)
        if translated_signature != source_signature:
            errors.append(f"{catalog_path}:{key!r}:{locale}: placeholders {translated_signature} do not match source {source_signature}")
    return errors


def validate(repo: Path) -> list[str]:
    errors: list[str] = []
    for path in catalog_paths(repo):
        catalog = load_catalog(path)
        for key, entry in catalog["strings"].items():
            if not isinstance(entry, dict):
                errors.append(f"{path}:{key!r}: string entry is not an object")
                continue
            localizations = entry.get("localizations", {})
            if not isinstance(localizations, dict):
                errors.append(f"{path}:{key!r}: localizations is not an object")
                continue
            for locale, localization in localizations.items():
                if not isinstance(localization, dict):
                    errors.append(f"{path}:{key!r}:{locale}: localization is not an object")
                else:
                    errors.extend(validate_localization(path, key, locale, localization))
    return errors


def validate_translation_resources(repo: Path) -> list[str]:
    """Check source configuration coverage only, never remote project existence."""
    path = repo / ".tx/config"
    config = configparser.ConfigParser(interpolation=None, strict=True)
    try:
        with path.open(encoding="utf-8") as source:
            config.read_file(source)
    except (OSError, configparser.Error, UnicodeError) as error:
        return [f"translation configuration unavailable or invalid: {error}"]
    catalogs = {repo_relative(repo, path): load_catalog(path)["sourceLanguage"]
                for path in catalog_paths(repo)}
    seen: set[str] = set()
    errors: list[str] = []
    for section in config.sections():
        if section == "main":
            continue
        resource = config[section]
        source = resource.get("source_file", "")
        if source not in catalogs:
            errors.append(f"{section}: source_file is not a known catalog: {source!r}")
            continue
        if source in seen:
            errors.append(f"{section}: duplicate translation resource for {source}")
        seen.add(source)
        if resource.get("file_filter") != source:
            errors.append(f"{section}: XCSTRINGS file_filter must equal source_file")
        if resource.get("type") != "XCSTRINGS":
            errors.append(f"{section}: translation resource type must be XCSTRINGS")
        if resource.get("source_lang") != catalogs[source]:
            errors.append(f"{section}: source_lang must match the catalog sourceLanguage")
    for source in sorted(set(catalogs) - seen):
        errors.append(f"missing translation resource for {source}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--inventory-out", type=Path, help="write deterministic inventory JSON")
    parser.add_argument("--check", action="store_true", help="fail if validation finds structural defects")
    parser.add_argument("--check-transifex", action="store_true", help="check local resource coverage, not remote project setup")
    args = parser.parse_args()
    try:
        record = inventory(args.repo)
        errors = validate(args.repo)
        if args.check_transifex:
            errors.extend(validate_translation_resources(args.repo))
    except CatalogError as error:
        print(json.dumps({"status": "invalid", "errors": [str(error)]}, indent=2, sort_keys=True))
        return 1
    if args.inventory_out:
        args.inventory_out.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    payload = {"status": "passed" if not errors else "invalid", "catalogs": len({entry["catalog"] for entry in record["entries"]}), "entries": len(record["entries"]), "errors": errors}
    print(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True))
    return 1 if (args.check or args.check_transifex) and errors else 0


if __name__ == "__main__":
    sys.exit(main())
