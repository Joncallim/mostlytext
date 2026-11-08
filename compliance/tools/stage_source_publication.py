#!/usr/bin/env python3
"""Stage a private, review-only versioned source archive from exact local evidence.

This command never uploads, changes inventory offer status, or claims that the
review packages are approved complete corresponding source.
"""

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tarfile
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compliance as gate
import prepare_graphviz_offer as graphviz_offer
import verify_d2_offer as d2_offer


ROOT = Path(__file__).resolve().parents[2]
D2_ARCHIVE_SHA256 = "07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02"
ARCHIVE_NAME = {
    "d2": "d2-source-review-bundle.tar.gz",
    "graphviz": "graphviz-source-review.tar.gz",
}
REVIEW_LIMIT = (
    "Private review snapshot only. The D2 and Graphviz packages have not been "
    "approved as complete corresponding source. No anonymous public retrieval, "
    "final signed-artifact match, independent rights clearance or release is claimed."
)


def sha(body):
    return hashlib.sha256(body).hexdigest()


def require_regular_file(path):
    if path.is_symlink() or not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"Required input is not a regular file: {path}")


def release_identity(inventory):
    product = inventory.get("product", {})
    version = product.get("version", "")
    if product.get("name") != "MostlyText" or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected one planned MostlyText release version")
    components = {row["id"]: row for row in inventory.get("components", [])}
    for component, page in (("d2", "d2"), ("viz-js", "graphviz")):
        if component not in components or "source_offer" not in components[component]:
            raise ValueError(f"Missing required source offer: {component}")
        offer = components[component]["source_offer"]
        expected = f"https://mostlytext.app/opensource/{version}/{page}/"
        if (offer.get("status") != "planned" or offer.get("location") != expected
                or offer.get("materials") or offer.get("verification")):
            raise ValueError(f"{component} is not an unverified planned source offer")
    return version


def page(component, archive_name, archive_bytes, version, patch=None):
    title = "D2" if component == "d2" else "Graphviz and Viz.js"
    package = (f'<li><a href="{html.escape(archive_name)}">{title} local review package</a> '
               f'({len(archive_bytes)} bytes; SHA-256 {sha(archive_bytes)})</li>')
    if patch is not None:
        package += (f'\n<li><a href="d2-browser.patch">D2 browser patch</a> '
                    f'({len(patch)} bytes; SHA-256 {sha(patch)})</li>')
    return ("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"robots\" content=\"noindex\">"
            f"<title>{title} source review — MostlyText {version}</title></head><body>\n"
            f"<h1>{title} — MostlyText {version} source review</h1>\n"
            f"<p>{REVIEW_LIMIT}</p>\n<ul>\n{package}\n</ul>\n"
            '<p><a href="../SHA256SUMS">All staged checksums</a></p>\n'
            "</body></html>\n").encode()


def material_files(version, notices, sbom, d2_archive, graphviz_archive, patch):
    prefix = version + "/"
    files = {
        prefix + "THIRD_PARTY_NOTICES.md": notices,
        prefix + "sbom.cdx.json": sbom,
        prefix + "d2/" + ARCHIVE_NAME["d2"]: d2_archive,
        prefix + "d2/d2-browser.patch": patch,
        prefix + "graphviz/" + ARCHIVE_NAME["graphviz"]: graphviz_archive,
        prefix + "d2/index.html": page("d2", ARCHIVE_NAME["d2"], d2_archive, version, patch),
        prefix + "graphviz/index.html": page("graphviz", ARCHIVE_NAME["graphviz"],
                                              graphviz_archive, version),
    }
    checksums = "".join(f"{sha(files[name])}  {name[len(prefix):]}\n" for name in sorted(files))
    files[prefix + "SHA256SUMS"] = checksums.encode()
    return files


def expected_stage(root, graphviz_inputs, graphviz_archive, d2_archive):
    report = gate.check(root)
    if report.errors:
        raise ValueError("Ordinary source compliance failed: " + "; ".join(report.errors[:3]))
    inventory_path = root / "compliance/inventory.json"
    require_regular_file(inventory_path)
    version = release_identity(json.loads(inventory_path.read_text()))
    for path in (graphviz_archive, d2_archive):
        require_regular_file(path)
    d2_body = d2_archive.read_bytes()
    if sha(d2_body) != D2_ARCHIVE_SHA256:
        raise ValueError("D2 archive differs from the reviewed immutable bytes")
    d2_facts = d2_offer.verify(
        d2_archive, root / "compliance/evidence/d2-0.1.33/source-graph.json",
        root / "MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js",
        root / "compliance/evidence/d2-0.1.33/offer-manifest.json"
    )
    with tarfile.open(d2_archive, "r:gz") as archive:
        patch = archive.extractfile("patches/d2-browser.patch").read()
    graphviz_bodies, graphviz_manifest = graphviz_offer.payload(root, graphviz_inputs)
    graphviz_offer.verify_archive(graphviz_archive, graphviz_bodies)
    graphviz_body = graphviz_archive.read_bytes()
    if graphviz_body != graphviz_offer.encode(graphviz_bodies):
        raise ValueError("Graphviz archive differs from the current deterministic review snapshot")
    notices_path = root / "compliance/generated/THIRD_PARTY_NOTICES.md"
    sbom_path = root / "compliance/generated/sbom.cdx.json"
    for path in (notices_path, sbom_path):
        require_regular_file(path)
    notices, sbom = notices_path.read_bytes(), sbom_path.read_bytes()
    files = material_files(version, notices, sbom, d2_body, graphviz_body, patch)
    receipt = {
        "schema": 1, "status": "private-review-only", "version": version,
        "limits": REVIEW_LIMIT,
        "inventory_sha256": sha(inventory_path.read_bytes()),
        "d2_review": d2_facts,
        "graphviz_review": {"files": len(graphviz_manifest["files"]),
                             "status": graphviz_manifest["status"]},
        "files": [{"path": name, "size": len(body), "sha256": sha(body)}
                  for name, body in sorted(files.items())],
    }
    files["REVIEW_ONLY.json"] = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode()
    return files, receipt


def verify_stage(output, expected):
    actual = {}
    directories = set()
    for directory, folders, names in os.walk(output, followlinks=False):
        for name in folders + names:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError("Staged snapshot contains a symlink")
        directories.update((Path(directory) / name).relative_to(output).as_posix()
                           for name in folders)
        for name in names:
            path = Path(directory) / name
            require_regular_file(path)
            actual[path.relative_to(output).as_posix()] = path.read_bytes()
    if set(actual) != set(expected):
        raise ValueError("Staged snapshot file set differs")
    required_directories = {str(Path(name).parent) for name in expected if "/" in name}
    required_directories |= {str(parent) for name in expected
                             for parent in Path(name).parents if str(parent) != "."}
    if directories != required_directories:
        raise ValueError("Staged snapshot directory set differs")
    for name, body in expected.items():
        if actual[name] != body:
            raise ValueError("Staged snapshot contents differ: " + name)


def stage(output, files, *, verify_only=False):
    if output.is_symlink() or not output.parent.is_dir():
        raise ValueError("Output parent must exist and output must not be a symlink")
    if verify_only:
        if not output.is_dir():
            raise ValueError("No staged snapshot to verify")
        verify_stage(output, files)
        return
    if output.exists():
        raise ValueError("Refusing to overwrite a staged snapshot")
    temporary = Path(tempfile.mkdtemp(prefix=".source-review-", dir=output.parent))
    try:
        for name, body in sorted(files.items()):
            target = temporary / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as stream:
                stream.write(body)
        verify_stage(temporary, files)
        temporary.rename(output)
    except BaseException:
        shutil.rmtree(temporary)
        raise


def require_private_output(root, output):
    if output.resolve().is_relative_to(root.resolve()):
        raise ValueError("Private staging output must be outside the repository")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--graphviz-inputs", type=Path, required=True)
    parser.add_argument("--graphviz-archive", type=Path, required=True)
    parser.add_argument("--d2-archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.absolute()
    require_private_output(root, output)
    files, receipt = expected_stage(root, args.graphviz_inputs, args.graphviz_archive,
                                    args.d2_archive)
    stage(output, files, verify_only=args.verify_only)
    print(json.dumps({"status": receipt["status"], "version": receipt["version"],
                      "files": len(receipt["files"]), "output": str(output)}, sort_keys=True))


if __name__ == "__main__":
    main()
