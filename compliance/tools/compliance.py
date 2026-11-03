#!/usr/bin/env python3
"""Third-party licence, provenance and SBOM gate for MostlyText (#148).

The distribution inventory (`compliance/inventory.json`) is the single record
of every third-party component the app ships. This tool:

* `check`   verifies the inventory against the source tree: recorded digests,
            licence texts, unregistered files, SwiftPM manifests and (when it
            exists) the Package.resolved lock file. `--release` adds the
            release-only rules: nothing pending, no open items, every
            source-availability location verified, lock file present.
            `--artifact PATH` also checks a built .app or DMG mount.
* `notices` writes compliance/generated/THIRD_PARTY_NOTICES.md.
* `sbom`    writes compliance/generated/sbom.cdx.json (CycloneDX 1.5).

Output is deterministic: no timestamps, sorted keys, stable ordering. The
tool uses only the Python standard library and never touches the network,
credentials or private files.
"""

from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import os
import re
import stat
import sys
import uuid
from pathlib import Path

INVENTORY = "compliance/inventory.json"
GENERATED = "compliance/generated"
NOTICES = f"{GENERATED}/THIRD_PARTY_NOTICES.md"
SBOM = f"{GENERATED}/sbom.cdx.json"

REQUIRED_FIELDS = ("id", "name", "kind", "version", "upstream", "licence", "copyright", "licence_texts", "provenance")
SKIP_DIRS = {".git", ".build", ".swiftpm", "DerivedData", "xcuserdata", "node_modules"}


# --------------------------------------------------------------------------
# Helpers


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Translate a repository glob (`*`, `**`, `?`) into an anchored regex."""
    out, i = [], 0
    while i < len(pattern):
        char = pattern[i]
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif char == "*":
            out.append("[^/]*")
            i += 1
        elif char == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(char))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(glob_to_regex(p).match(path) for p in patterns)


def normalise_url(url: str) -> str:
    url = url.strip().lower().rstrip("/")
    return url[:-4] if url.endswith(".git") else url


def load_inventory(root: Path) -> dict:
    with (root / INVENTORY).open(encoding="utf-8") as handle:
        return json.load(handle)


def walk_distributable(root: Path) -> list[str]:
    """Every file under MacDown2/, as repository-relative POSIX paths."""
    base = root / "MacDown2"
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            found.append((Path(dirpath) / name).relative_to(root).as_posix())
    return found


# --------------------------------------------------------------------------
# Manifest and lock-file parsing

PACKAGE_CALL = re.compile(r"\.package\s*\(")
URL_ARG = re.compile(r'\burl\s*:\s*"([^"\\]*)"')
PATH_ARG = re.compile(r'\bpath\s*:\s*"([^"\\]*)"')
REQUIREMENT = re.compile(r'\b(branch|revision|exact|from)\s*:\s*"([^"]+)"')
RANGE_FORM = re.compile(r"\.(upToNextMinor|upToNextMajor)\s*\(")


def strip_swift_comments(text: str) -> str:
    """Remove // and /* */ comments, keeping string literals and line breaks.

    This is a lexer for comments and strings only, not a Swift parser: it is
    just enough to stop a commented-out `.package(...)` from counting and a
    `//` inside a URL from being mistaken for a comment.
    """
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith('"""', i):  # multi-line string literal
            end = text.find('"""', i + 3)
            end = n if end < 0 else end + 3
            out.append(text[i:end])
            i = end
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] not in '"\n':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = n if end < 0 else end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append("\n" * text.count("\n", i, end))
            i = end
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def call_arguments(text: str, start: int) -> str | None:
    """Text between the parenthesis before `start` and its matching close."""
    depth, i, n = 1, start, len(text)
    while i < n:
        char = text[i]
        if char == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start:i]
        i += 1
    return None


def requirement_of(args: str) -> dict:
    """The version requirement of a `.package(url:…)` call, in a comparable form.

    Keyword forms (`exact:`, `from:`, `branch:`, `revision:`) become
    {keyword: value}. `.upToNextMinor/Major(from:)` also records the form.
    Anything else (for example a `"1.0.0"..<"2.0.0"` range) is kept verbatim
    under `unparsed`, so it can never silently match a recorded requirement.
    """
    requirement = dict(REQUIREMENT.findall(args))
    if form := RANGE_FORM.search(args):
        requirement["form"] = form.group(1)
    if not requirement:
        remainder = URL_ARG.sub("", args)
        requirement["unparsed"] = " ".join(remainder.replace(",", " ").split())
    return requirement


def parse_manifest(text: str) -> tuple[list[tuple[str, dict]], list[str], list[str]]:
    """Return (url dependencies, local-path dependencies, unrecognised calls).

    Works on single-line and multi-line `.package(...)` declarations alike.
    Anything that looks like a package declaration but isn't a plain `url:`
    or `path:` form (a registry `id:`, an interpolated URL, unbalanced
    parentheses) is returned as unrecognised so the check fails closed.
    """
    code = strip_swift_comments(text)
    urls, paths, unknown = [], [], []
    for call in PACKAGE_CALL.finditer(code):
        args = call_arguments(code, call.end())
        snippet = " ".join(code[call.start():call.end() + 80].split())
        if args is None:
            unknown.append(snippet)
        elif url := URL_ARG.search(args):
            urls.append((url.group(1), requirement_of(args)))
        elif path := PATH_ARG.search(args):
            paths.append(path.group(1))
        else:
            unknown.append(" ".join(f".package({args})".split()))
    return urls, paths, unknown


XCODEGEN_REQUIREMENT = {"exactVersion": "exact", "version": "exact", "from": "from", "majorVersion": "from",
                        "minorVersion": "from", "branch": "branch", "revision": "revision"}


def parse_xcodegen_packages(text: str) -> tuple[list[tuple[str, dict]], list[str], list[str]]:
    """Remote packages (with requirements), local paths and unreadable entries from project.yml's `packages:`.

    XcodeGen's requirement keys are mapped onto the same form the
    Package.swift scanner produces, so both are compared with the inventory
    the same way. `minorVersion` is recorded as the upToNextMinor form; any
    other key (such as minVersion/maxVersion) is kept as `unparsed`. The
    indentation is taken from the file. Any `url:` or `path:` under
    `packages:` that isn't read as a block-style field (for example a
    flow-style `{url: …}` entry) is returned as unreadable, so the check
    fails closed.
    """
    packages: dict[str, dict] = {}
    unknown: list[str] = []
    inside, name, name_indent = False, None, None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            inside, name, name_indent = line.strip() == "packages:", None, None
            continue
        if not inside:
            continue
        name_indent = indent if name_indent is None else name_indent
        if indent == name_indent and (match := re.fullmatch(r"(\S[^:]*):", line.strip())):
            name = match.group(1)
            packages[name] = {}
        elif indent > name_indent and name and (match := re.fullmatch(r"(\w+)\s*:\s*['\"]?([^'\"\s]+)['\"]?", line.strip())):
            packages[name][match.group(1)] = match.group(2)
        elif re.search(r"\b(url|path)\s*:", line):
            unknown.append(line.strip())
    urls, paths = [], []
    for fields in packages.values():
        if "path" in fields:
            paths.append(fields["path"])
        if "url" in fields:
            requirement: dict = {}
            for key, value in fields.items():
                if key in ("url", "path", "github"):
                    continue
                if key in XCODEGEN_REQUIREMENT:
                    requirement[XCODEGEN_REQUIREMENT[key]] = value
                    if key == "minorVersion":
                        requirement["form"] = "upToNextMinor"
                else:
                    requirement["unparsed"] = f"{key}: {value}"
            urls.append((fields["url"], requirement))
    return urls, paths, unknown


def parse_lockfile(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    pins = data.get("pins") or data.get("object", {}).get("pins", [])
    out = []
    for pin in pins:
        location = pin.get("location") or pin.get("repositoryURL", "")
        state = pin.get("state", {})
        out.append({"location": location, "revision": state.get("revision"), "version": state.get("version"), "branch": state.get("branch")})
    return out


# --------------------------------------------------------------------------
# Checks


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def check(root: Path, release: bool = False, artifact: Path | None = None) -> Report:
    report = Report()
    inventory = load_inventory(root)
    components = inventory.get("components", [])
    ids = [c.get("id") for c in components]
    for duplicate in sorted({i for i in ids if ids.count(i) > 1}):
        report.error(f"duplicate component id: {duplicate}")

    first_party_text = root / inventory["first_party"]["licence_text"]
    if not first_party_text.is_file():
        report.error(f"first-party licence text missing: {inventory['first_party']['licence_text']}")

    by_url: dict[str, dict] = {}
    for component in components:
        cid = component.get("id", "<no id>")
        for field in REQUIRED_FIELDS:
            if field not in component or component[field] in (None, "", []):
                report.error(f"{cid}: missing required field '{field}'")
        if component.get("kind") == "swiftpm":
            by_url[normalise_url(component["upstream"])] = component

        for text in component.get("licence_texts", []):
            path = root / text["path"]
            if not path.is_file():
                report.error(f"{cid}: licence/notice text missing: {text['path']}")
            elif sha256_file(path) != text.get("sha256"):
                report.error(f"{cid}: licence/notice text changed (digest mismatch): {text['path']}")

        for entry in component.get("files", []):
            path = root / entry["path"]
            if not path.is_file():
                report.error(f"{cid}: distributed file missing: {entry['path']}")
            elif sha256_file(path) != entry["sha256"]:
                report.error(f"{cid}: distributed file digest mismatch: {entry['path']}")

        # Runtime resources: what must appear in the built app. An entry with
        # a repository path must still match that file, so a changed engine
        # or theme can't leave a stale artifact contract behind.
        if component.get("kind") == "vendored-bundle" and not component.get("runtime_resources"):
            report.error(f"{cid}: a vendored bundle must declare runtime_resources so the built app can be checked")
        for resource in component.get("runtime_resources", []):
            if not resource.get("name") or not re.fullmatch(r"[0-9a-f]{64}", resource.get("sha256", "")):
                report.error(f"{cid}: runtime resource needs a name and a SHA-256: {resource}")
            elif resource.get("path"):
                path = root / resource["path"]
                if not path.is_file():
                    report.error(f"{cid}: runtime resource source missing: {resource['path']}")
                elif sha256_file(path) != resource["sha256"]:
                    report.error(f"{cid}: runtime resource digest is stale: {resource['path']}")

        offer = component.get("source_offer")
        if offer and offer.get("required"):
            if not offer.get("location"):
                report.error(f"{cid}: source availability is required ({offer.get('reason', 'copyleft')}) but no source location is recorded")
            elif release and offer.get("status") != "verified":
                report.error(f"{cid}: source location {offer['location']} is '{offer.get('status')}', not verified by anonymous retrieval")

        if release:
            if component.get("provenance") != "verified":
                report.error(f"{cid}: provenance is '{component.get('provenance')}', not verified")
            if component.get("resolution") == "pending-lockfile":
                report.error(f"{cid}: revision still pending the LC-05 lock file")
            for item in component.get("open_items", []):
                report.error(f"{cid}: open item: {item}")

    # Unregistered distributed content. `owns` says which component a path
    # belongs to; it doesn't make the path compliant. A file inside a
    # wildcard-owned boundary (for example a vendored package's `**`) must
    # also be accounted for by that component: in its audited `files`, its
    # licence texts or its runtime resources. It can't fall back to the
    # first-party globs, so a file added to a vendored package can't pass as
    # first-party code either. Exact-path `owns` entries are already an
    # explicit enumeration.
    owned = [(c["id"], p) for c in components for p in c.get("owns", [])]
    accounted = {
        c["id"]: {f["path"] for f in c.get("files", [])}
        | {t["path"] for t in c.get("licence_texts", [])}
        | {r["path"] for r in c.get("runtime_resources", []) if r.get("path")}
        for c in components
    }
    registered_files = {f["path"] for c in components for f in c.get("files", [])}
    for rel in walk_distributable(root):
        if matches_any(rel, inventory.get("not_distributed", [])):
            continue
        owners = [cid for cid, pattern in owned if glob_to_regex(pattern).match(rel)]
        if owners:
            wildcard_owners = [cid for cid, pattern in owned if "*" in pattern and glob_to_regex(pattern).match(rel)]
            unaccounted = [cid for cid in wildcard_owners if rel not in accounted[cid]]
            if unaccounted and len(unaccounted) == len(owners):
                report.error(f"{unaccounted[0]}: file inside its owned boundary is not in its audited files (add it with its digest, or mark it not_distributed): {rel}")
            continue
        if rel in registered_files or matches_any(rel, inventory["first_party"]["paths"]):
            continue
        report.error(f"unregistered distributed file (add it to {INVENTORY} or to first_party): {rel}")
    for cid, pattern in owned:
        if "*" not in pattern and not (root / pattern).exists():
            report.error(f"{cid}: owned path does not exist: {pattern}")

    # SwiftPM manifests: the listed ones plus every Package.swift under
    # MacDown2/, so a newly added local package can't bring in an unchecked
    # dependency.
    build_only = {normalise_url(u) for u in inventory.get("build_only_packages", [])}
    manifests = sorted(set(inventory.get("manifests", [])) | {p for p in walk_distributable(root) if p.endswith("/Package.swift")})
    for manifest in manifests:
        manifest_path = root / manifest
        if not manifest_path.is_file():
            report.error(f"manifest listed in inventory is missing: {manifest}")
            continue
        urls, paths, unknown = parse_manifest(manifest_path.read_text(encoding="utf-8"))
        for snippet in unknown:
            report.error(f"{manifest}: unrecognised package declaration (only url: and path: forms can be checked): {snippet}")
        for url, requirement in urls:
            key = normalise_url(url)
            if key in build_only:
                continue
            component = by_url.get(key)
            if component is None:
                report.error(f"{manifest}: dependency {url} is not registered in the inventory")
                continue
            recorded = component.get("manifest_requirement")
            if recorded is not None and recorded != requirement:
                report.error(f"{component['id']}: stale mapping: {manifest} requires {requirement}, inventory records {recorded}")
        for rel in paths:
            target = (manifest_path.parent / rel).resolve().relative_to(root.resolve()).as_posix()
            if not any(glob_to_regex(p).match(target + "/Package.swift") for _, p in owned):
                report.error(f"{manifest}: local package {target} is not owned by any inventory component")

    # XcodeGen can add packages to the app directly, bypassing Package.swift.
    project = root / "MacDown2/project.yml"
    if project.is_file():
        urls, paths, unknown = parse_xcodegen_packages(project.read_text(encoding="utf-8"))
        for entry in unknown:
            report.error(f"MacDown2/project.yml: unrecognised package entry (only block-style url:/path: entries can be checked): {entry}")
        for url, requirement in urls:
            key = normalise_url(url)
            if key in build_only:
                continue
            component = by_url.get(key)
            if component is None:
                report.error(f"MacDown2/project.yml: package {url} is not registered in the inventory")
            elif component.get("manifest_requirement") is not None and component["manifest_requirement"] != requirement:
                report.error(f"{component['id']}: stale mapping: MacDown2/project.yml requires {requirement}, inventory records {component['manifest_requirement']}")
        for rel in paths:
            target = (project.parent / rel).resolve()
            try:
                inside = target.relative_to((root / "MacDown2").resolve())
            except ValueError:
                inside = None
            if inside is None or not (target / "Package.swift").is_file():
                report.error(f"MacDown2/project.yml: local package {rel} is outside MacDown2/ or has no Package.swift, so its dependencies can't be checked")

    # Lock file. Until the inventory has been reconciled with the LC-05 lock
    # file (`lockfile_enforced`), lock-file findings are reported as
    # unverified so the lock file itself can land without this gate going
    # red. Release mode is always strict.
    strict_lock = release or inventory.get("lockfile_enforced", False)
    lock_problem = report.error if strict_lock else report.warn
    lockfiles = [root / p for p in inventory.get("lockfiles", []) if (root / p).is_file()]
    if not lockfiles:
        lock_problem("no Package.resolved found; SwiftPM revisions cannot be verified without the committed lock file (LC-05)")
    pinned_urls: set[str] = set()
    for lockfile in lockfiles:
        rel = lockfile.relative_to(root).as_posix()
        for pin in parse_lockfile(lockfile):
            key = normalise_url(pin["location"])
            pinned_urls.add(key)
            if key in build_only:
                continue
            component = by_url.get(key)
            if component is None:
                lock_problem(f"{rel}: resolved package {pin['location']} is not registered in the inventory")
            elif component.get("revision") != pin["revision"]:
                lock_problem(f"{component['id']}: stale mapping: {rel} resolves {pin['revision']}, inventory records {component.get('revision')}")
    if lockfiles:
        for key, component in sorted(by_url.items()):
            if key not in pinned_urls:
                lock_problem(f"{component['id']}: registered SwiftPM component is absent from the lock file")

    # Generated outputs must match the inventory.
    for rel, render in ((NOTICES, render_notices), (SBOM, render_sbom)):
        path = root / rel
        try:
            expected = render(root, inventory)
        except OSError as error:
            report.error(f"cannot regenerate {rel}: {error.strerror}: {error.filename}")
            continue
        if not path.is_file():
            report.error(f"generated file missing: {rel} (run compliance.py notices/sbom)")
        elif path.read_text(encoding="utf-8") != expected:
            report.error(f"generated file is stale: {rel} (run compliance.py notices/sbom)")

    if artifact is not None:
        check_artifact(root, inventory, artifact, report)
    return report


def resolve_artifact_link(path: Path, artifact: Path) -> Path:
    """Resolve a relative link chain without inspecting any outside component.

    The artifact is a canonical, stable prepared tree. This is containment
    validation, not a snapshot or protection against concurrent replacement.
    """
    pending = deque(path.relative_to(artifact).parts)
    current, links = artifact, 0
    while pending:
        part = pending.popleft()
        if part == "..":
            if current == artifact:
                raise ValueError("link leaves the artifact")
            current = current.parent
            continue
        if part in (".", ""):
            continue
        candidate = current / part
        mode = candidate.lstat().st_mode
        if stat.S_ISLNK(mode):
            links += 1
            if links > 40:
                raise ValueError("cyclic or excessive link chain")
            target = os.readlink(candidate)
            if os.path.isabs(target):
                raise ValueError("absolute link target")
            # Preserve dot/empty components: file.js/.. and file.js/ are
            # invalid paths, not aliases to be normalized into valid ones.
            pending.extendleft(reversed(target.split("/")))
        else:
            if pending and not stat.S_ISDIR(mode):
                raise ValueError("non-directory link component")
            current = candidate
    return current


def artifact_digests(artifact: Path, report: Report) -> dict[str, list[str]]:
    """Count regular files and safe file aliases; never follow directory aliases."""
    shipped: dict[str, list[str]] = {}

    def unreadable(error: OSError) -> None:
        report.error(f"artifact directory unreadable: {error}")

    for dirpath, dirnames, filenames in os.walk(artifact, onerror=unreadable, followlinks=False):
        # Inspect directory links as well as filenames, including dangling links.
        for name in sorted(dirnames + filenames):
            path = Path(dirpath) / name
            rel = path.relative_to(artifact).as_posix()
            try:
                mode = path.lstat().st_mode
                if stat.S_ISLNK(mode):
                    if name in dirnames:
                        dirnames.remove(name)
                    # The DMG's installation shortcut is not shipped runtime.
                    # No app-level, nested or differently targeted escape qualifies.
                    if (path.parent == artifact and name == "Applications"
                            and not artifact.name.lower().endswith(".app")
                            and not os.path.lexists(artifact / "Contents")
                            and os.readlink(path) == "/Applications"):
                        continue
                    try:
                        path = resolve_artifact_link(path, artifact)
                        mode = path.lstat().st_mode
                    except (OSError, ValueError) as error:
                        report.error(f"unsafe artifact link: {rel}: {error}")
                        continue
                if stat.S_ISDIR(mode):
                    continue
                if not stat.S_ISREG(mode):
                    report.error(f"unsupported artifact object: {rel}")
                    continue
                shipped.setdefault(sha256_file(path), []).append(rel)
            except OSError as error:
                report.error(f"artifact file unreadable: {rel}: {error}")
    return shipped


def check_artifact(root: Path, inventory: dict, artifact: Path, report: Report) -> None:
    """Compare a built app (or mounted DMG) with the inventory's artifact contract.

    Proves three things by SHA-256, anywhere inside the artifact:
    1. every component's runtime_resources is present;
    2. the required first-party files (licence, generated notices) are present;
    3. no file with a registered extension (scripts, WebAssembly, fonts) ships
       unless it is a known runtime resource or a first-party source file.
    Compiled code can't be matched this way; the source-tree check and the
    SBOM cover it.
    """
    try:
        artifact = artifact.resolve(strict=True)
        if not artifact.is_dir():
            report.error(f"artifact is not a directory: {artifact}")
            return
    except (OSError, RuntimeError) as error:
        report.error(f"artifact not found or unreadable: {artifact}: {error}")
        return
    contract = inventory.get("artifact", {})
    shipped = artifact_digests(artifact, report)

    known: set[str] = set()
    for component in inventory["components"]:
        for resource in component.get("runtime_resources", []):
            known.add(resource["sha256"])
            if resource["sha256"] not in shipped:
                report.error(f"{component['id']}: required runtime resource {resource['name']} ({resource['sha256'][:12]}…) is not in the artifact")

    for rel in contract.get("required_first_party", []):
        path = root / rel
        digest = sha256_file(path) if path.is_file() else None
        if digest is None or digest not in shipped:
            report.error(f"artifact does not contain the generated {Path(rel).name} from this repository" if rel.startswith(GENERATED)
                         else f"artifact does not contain first-party {rel} from this repository")
        if digest:
            known.add(digest)

    extensions = tuple(contract.get("registered_extensions", []))
    first_party = inventory["first_party"]["paths"]
    for rel in walk_distributable(root):
        if rel.endswith(extensions) and matches_any(rel, first_party):
            known.add(sha256_file(root / rel))
    for digest, paths in sorted(shipped.items()):
        for rel in paths:
            if rel.lower().endswith(extensions) and digest not in known:
                report.error(f"artifact ships an unregistered runtime file: {rel}")


# --------------------------------------------------------------------------
# Rendering


def render_notices(root: Path, inventory: dict) -> str:
    product = inventory["product"]["name"]
    lines = [
        f"# {product} third-party notices",
        "",
        f"{product} is free software under the MIT licence, continuing the MIT",
        "licence of MacDown, from which it descends. Its own licence and",
        "copyright lines are in `LICENSE`.",
        "",
        f"{product} also includes the third-party components below. Each keeps its",
        "own licence. The full text each licence requires is reproduced after the",
        "summary. Where a licence requires source code to be available, the",
        "location is listed with the component.",
        "",
        "This file is generated from `compliance/inventory.json` by",
        "`compliance/tools/compliance.py notices`. Do not edit it by hand.",
        "",
        "## Summary",
        "",
        "| Component | Version | Licence |",
        "|---|---|---|",
    ]
    components = sorted(inventory["components"], key=lambda c: c["name"].lower())
    for component in components:
        lines.append(f"| {component['name']} | {component['version']} | {component['licence']} |")
    lines.append("")
    for component in components:
        lines += ["---", "", f"## {component['name']}", ""]
        lines.append(f"- Version: {component['version']}")
        lines.append(f"- Upstream: {component['upstream']}")
        if component.get("revision"):
            lines.append(f"- Revision: `{component['revision']}`")
        lines.append(f"- Licence: {component['licence']}")
        for holder in component["copyright"]:
            lines.append(f"- {holder}")
        if component.get("modifications"):
            lines.append(f"- Local modifications: {component['modifications']}")
        offer = component.get("source_offer")
        if offer and offer.get("required"):
            lines.append(f"- Source code: {offer['location']}")
        if component.get("fonts"):
            lines.append("- Fonts: " + ", ".join(f"{f['name']} ({f['licence']})" for f in component["fonts"]))
        if component.get("nested"):
            lines.append("- Bundles: " + ", ".join(n["name"] for n in component["nested"]))
        lines.append("")
        for text in component["licence_texts"]:
            body = (root / text["path"]).read_text(encoding="utf-8", errors="replace").rstrip()
            lines += [f"### {Path(text['path']).name}", "", "```text", body.replace("```", "``​`"), "```", ""]
    return "\n".join(lines).rstrip() + "\n"


def purl(component: dict) -> str | None:
    if component.get("npm"):
        name, _, version = component["npm"].rpartition("@")
        return f"pkg:npm/{name.replace('@', '%40')}@{version}"
    match = re.match(r"https://github\.com/([^/]+)/([^/]+)$", component["upstream"])
    if match and component.get("revision"):
        return f"pkg:github/{match.group(1).lower()}/{match.group(2).lower()}@{component['revision']}"
    return None


def render_sbom(root: Path, inventory: dict) -> str:
    entries = []
    for component in sorted(inventory["components"], key=lambda c: c["id"]):
        entry = {
            "bom-ref": component["id"],
            "type": "data" if component["kind"] == "data" else "library",
            "name": component["name"],
            "version": component["version"],
            "licenses": [{"expression": component["licence"]}],
            "externalReferences": [{"type": "vcs", "url": component["upstream"]}],
            "properties": [
                {"name": "mostlytext:kind", "value": component["kind"]},
                {"name": "mostlytext:provenance", "value": component["provenance"]},
                {"name": "mostlytext:resolution", "value": component.get("resolution", "")},
            ],
        }
        if ref := purl(component):
            entry["purl"] = ref
        if component.get("files"):
            content = "".join(f"{f['path']}\0{f['sha256']}\n" for f in sorted(component["files"], key=lambda f: f["path"]))
            entry["hashes"] = [{"alg": "SHA-256", "content": hashlib.sha256(content.encode()).hexdigest()}]
            entry["properties"].append({"name": "mostlytext:file-count", "value": str(len(component["files"]))})
        if component.get("modifications"):
            entry["pedigree"] = {"notes": component["modifications"]}
        entries.append(entry)
    body = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "component": {"bom-ref": "product", "type": "application", "name": inventory["product"]["name"],
                          "version": inventory["product"]["version"], "licenses": [{"license": {"id": inventory["first_party"]["licence"]}}]},
        },
        "components": entries,
        "dependencies": [{"ref": "product", "dependsOn": [e["bom-ref"] for e in entries]}],
    }
    serial = uuid.uuid5(uuid.NAMESPACE_URL, "mostlytext-sbom:" + hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest())
    body = {"serialNumber": f"urn:uuid:{serial}", **body}
    return json.dumps(body, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


# --------------------------------------------------------------------------
# CLI


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2], help="repository root")
    sub = parser.add_subparsers(dest="command", required=True)
    check_cmd = sub.add_parser("check", help="verify the inventory against the tree")
    check_cmd.add_argument("--release", action="store_true", help="apply release-only rules")
    check_cmd.add_argument("--artifact", type=Path, help="built .app or mounted DMG to compare")
    sub.add_parser("notices", help="write THIRD_PARTY_NOTICES.md")
    sub.add_parser("sbom", help="write the CycloneDX SBOM")
    args = parser.parse_args(argv)
    root = args.root.resolve()

    if args.command in ("notices", "sbom"):
        inventory = load_inventory(root)
        rel, render = (NOTICES, render_notices) if args.command == "notices" else (SBOM, render_sbom)
        (root / GENERATED).mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(render(root, inventory), encoding="utf-8")
        print(f"wrote {rel}")
        return 0

    report = check(root, release=args.release, artifact=args.artifact)
    for warning in report.warnings:
        print(f"UNVERIFIED: {warning}")
    for error in report.errors:
        print(f"FAIL: {error}")
    mode = "release" if args.release else "tree"
    if report.errors:
        print(f"compliance check ({mode}): {len(report.errors)} failure(s)")
        return 1
    print(f"compliance check ({mode}): passed, {len(report.warnings)} unverified item(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
