#!/usr/bin/env python3
"""Verify the retained D2 build-helper source capture without executing it.

This checks the immutable supplemental input packet. It does not prove the
publisher used this helper, reproduce D2, or approve a source offer.
"""

import hashlib
import io
import json
from pathlib import Path
import tarfile


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path("compliance/evidence/d2-build-inputs")
ARCHIVE = "terrastruct-ci-2594100a-source.tar.gz"
PREFIX = "terrastruct-ci-2594100a/"
ARCHIVE_SHA256 = "a2129160358307bc8c08049c78dd47767c0528f9370fb8b0704d607eeeb94d3b"
RECEIPT_SHA256 = "4a07ae2b08183eaefb44ee1b723cf156958700e0af4a1dcb943f1f081010f4ff"
ROOT_COMMIT = "581c91096b62d644fb5168313142c836b7e68e74"
SUBMODULE_COMMIT = "2594100ac939644f134e24edac7c9bcd569b99f6"


def sha256(body):
    return hashlib.sha256(body).hexdigest()


def verify_members(archive_bytes, expected):
    if not expected or "LICENSE" not in expected or len(expected) != 37:
        raise ValueError("D2 helper file manifest is incomplete")
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
        for member in archive:
            if not member.isfile() or not member.name.startswith(PREFIX):
                raise ValueError("D2 helper archive has an unexpected member type or path")
            relative = member.name[len(PREFIX):]
            if (not relative or relative.startswith("/") or "\\" in relative
                    or any(part in ("", ".", "..") for part in relative.split("/"))
                    or relative in seen or relative not in expected):
                raise ValueError("D2 helper archive has an unsafe, duplicate or extra member")
            seen.add(relative)
            body = archive.extractfile(member).read()
            if sha256(body) != expected[relative] or len(body) != member.size:
                raise ValueError("D2 helper archive member differs: " + relative)
    if seen != set(expected):
        raise ValueError("D2 helper archive is missing recorded source files")
    return len(seen)


def verify(root=ROOT):
    evidence = root / EVIDENCE
    archive_path = evidence / ARCHIVE
    receipt_path = evidence / "verified-source-submodule.json"
    manifest_path = evidence / "manifest.json"
    for path in (archive_path, receipt_path, manifest_path):
        if path.is_symlink() or not path.is_file():
            raise ValueError("D2 helper evidence must be regular files")
    archive_bytes, receipt_bytes = archive_path.read_bytes(), receipt_path.read_bytes()
    if sha256(archive_bytes) != ARCHIVE_SHA256 or sha256(receipt_bytes) != RECEIPT_SHA256:
        raise ValueError("D2 helper archive or receipt differs from reviewed bytes")
    manifest = json.loads(manifest_path.read_text())
    if (manifest.get("files", {}).get(ARCHIVE) != ARCHIVE_SHA256
            or manifest.get("files", {}).get(receipt_path.name) != RECEIPT_SHA256):
        raise ValueError("D2 helper packet manifest differs from reviewed evidence")
    receipt = json.loads(receipt_bytes)
    if (receipt.get("root_commit") != ROOT_COMMIT or receipt.get("path") != "ci/sub"
            or receipt.get("commit") != SUBMODULE_COMMIT
            or receipt.get("declared_url") != "https://github.com/terrastruct/ci"):
        raise ValueError("D2 helper source identity differs")
    count = verify_members(archive_bytes, receipt.get("files_sha256"))
    return {"files": count, "archive_sha256": ARCHIVE_SHA256,
            "root_commit": ROOT_COMMIT, "submodule_commit": SUBMODULE_COMMIT,
            "scope": "retained source bytes only; publisher use and offer completeness unproved"}


if __name__ == "__main__":
    print(json.dumps(verify(), sort_keys=True))
