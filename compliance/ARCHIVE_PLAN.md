# Compliance archive plan (LC-09)

**Owner summary.** The current inventory requires corresponding-source offers
for Graphviz (EPL-2.0, compiled into Viz.js) and D2 (MPL-2.0, with a local
browser export patch and a narrowly rebuilt font-bearing WASM). This plan says
what we publish for each release, where, and how
we prove it can be downloaded. Independent review of other nested and build
inputs remains open; these two recorded offers do not clear those obligations.
The recommended home is
`mostlytext.app/opensource/<version>/` for the index pages, with large source
packages at an approved durable source-only location linked from those pages.
Source-only publication requires the owner's separate approval before the
binary release process.

Risks: a URL printed in a shipped app must keep working for as long as that
release is distributed, so the layout below is versioned and never reused.
Owning the domain doesn't prove availability, so every location is downloaded
anonymously before public promotion. Non-goals: this doesn't choose the web
host (E17 does), and it never publishes credentials, signing or update keys,
or private material.

## Layout for each release

```text
mostlytext.app/opensource/
  index.html                       list of releases (website/opensource/index.html)
  <version>/
    THIRD_PARTY_NOTICES.md          byte-identical to the copy inside the app
    sbom.cdx.json                   byte-identical to the release SBOM
    SHA256SUMS                      digests of every file in this folder and every linked package
    graphviz/index.html             Graphviz + Viz.js corresponding source (LC-02)
    d2/index.html                   D2 corresponding source and our patch (LC-03)
```

Large packages are published with the source-only publication described under "Order of work" (not as assets of an unpublished draft release). The
`graphviz/` and `d2/` pages link to them and list their SHA-256 digests.

## What each source page contains

| Component | Contents | Evidence to record in the inventory |
|---|---|---|
| Graphviz 16.0.0 via @viz-js/viz 3.30.0 | The upstream Graphviz 16.0.0 source archive; the viz-js 3.30.0 source at its release tag, including the Emscripten build scripts that produce the WebAssembly; the EPL-2.0 text and scoped CPL/VPSC, Expat, Emscripten and musl candidate notices; a note that we ship `dist/viz-global.js` from the npm package unmodified. CPL/EPL interpretation remains under review. | Archive URLs and SHA-256; upstream tag commits; `npm_file_sha256` already recorded |
| D2 via @terrastruct/d2 0.1.33 | The pinned D2 source/npm input, 16 Go module sources, Chroma source and narrow font patch, official Liberation Mono 2.00.5 TTF and deterministic WOFF conversion, browser export/payload patch procedure, ELK/Java and JavaScript Brotli source references, pinned D2 ELK modification history, Go runtime source, notices and build record. The exact historical publisher optimizer remains unattested. | Source revisions and archive SHA-256 values; patch/converter and output hashes; completed nested/per-file review, then verified public source-offer receipts. |

The inventory also records MIT, BSD, Apache-2.0, ISC, FTL, OFL and GUST terms,
mixed expressions, a Bison GPL text with its exception, and selected root
texts under `LicenseRef` identifiers. LC-01 covers distribution of the recorded
notices. The current inventory marks only Graphviz and D2 as requiring source
offers; that is not a completed review of nested code, per-file obligations or
whether every recorded build input is retained in the final binary. The SBOM
records the known versions and source references, including entries whose exact
original provenance remains unresolved.

## Retention and stable links

The [Graphviz input audit](evidence/viz-js-3.30.0/README.md) retains the exact
Graphviz and Viz.js archives/build records plus Expat 2.8.4, which the
WebAssembly build explicitly links. It also identifies separately licensed
Graphviz red-black tree, Luc Maisonobe-derived ellipse and Random kit sources
on the renderer's source-build paths. Include Expat's MIT text and these
verbatim nested notices in the reviewed Graphviz package; the sources are in
the retained archives. The archive digests match
the npm backend's publisher provenance; no independent rebuild or complete
runtime attribution audit is claimed. This preparation has not published a
source offer.

- Keep every release folder for as long as that release, or any update that
  could install it, is downloadable, and for at least three years after the
  last distribution. EPL-2.0 and MPL-2.0 don't set a period; three years is a
  conservative default.
- Never overwrite a published file. A correction goes in a new file, and
  `SHA256SUMS` records both.
- If hosting moves, redirect old URLs permanently (HTTP 301) to the new
  location and re-run the anonymous-download check.

## Verification before public promotion

1. Download every file listed in `SHA256SUMS` anonymously (no cookies, no
   GitHub login) from a network outside the build machine, and compare the
   digests.
2. Confirm that the app's `THIRD_PARTY_NOTICES.md` and `sbom.cdx.json` match
   the archive copies byte for byte.
3. Set `source_offer.status` to `"verified"` for Graphviz and D2 in
   `inventory.json` only after the independent download review. For each
   component, record the stable page/package URLs, exact sizes and SHA-256 in
   `source_offer.materials`; commit the credential-free HTTPS retrieval receipt
   under `compliance/evidence/source-offers/`, and pin its path and SHA-256 in
   `source_offer.verification`. Include the offered location itself among the
   fetched materials. Then run `compliance.py check --release --artifact <app>`.
   The offline checker detects missing, stale or inconsistent evidence; it
   cannot prove that a claimed fetch happened or that the URL remains live.

All of this can run in a cloud session except extracting the files from the
signed app, which needs the DMG, a step that can be done on any machine once
the DMG exists.

## Order of work

The earlier plan attached the packages to a **draft** GitHub Release and verified anonymous retrieval from there. A draft
release and its assets are unpublished and access-controlled, so anonymous retrieval from a draft always fails and
`source_offer` could never become `verified` before promotion, while `release/macos/sign-notarize-dmg.sh
--release-candidate` checks that before notarisation: a deadlock. The corresponding source is therefore published
**separately from, and before**, any binary:

1. **Preparation:** verify the local Graphviz and D2 review packages, patch and exact digests; finish the independent
   completeness and rights review (LC-02, LC-03). The existing packages are review objects, not approved offers.
2. **Source-only publication (needs the owner's explicit approval, `source-archive-authorization`):** publish the
   immutable, versioned corresponding-source objects (`THIRD_PARTY_NOTICES.md`, `sbom.cdx.json`, `SHA256SUMS`, the two
   source pages, the packages and patch) to the durable public location chosen in E17 — the website's
   `opensource/<version>/` folder and/or a source-only archive or release that contains **no application binary**. This is
   a public act; nothing is published until it is approved. Do not publish a binary, flip a draft release to public, or
   weaken the compliance check to make anonymous retrieval pass.
3. **Freeze** the final URLs and digests, then generate the final notices/SBOM from them, so the shipped app's
   `THIRD_PARTY_NOTICES.md` names locations that already exist.
4. **At E17:** build the final signed candidate; run the verification below against the already-public source location
   and the exact artifact.
5. **Before public promotion:** attach the evidence to MostlyText #14 and #4. Public promotion of the application remains a
   separate owner authorisation.

Test obligations: anonymous fetch of a draft-release asset fails (documented counterexample, so nobody rebuilds the
deadlock); a cookie-less fetch of every published object matches `SHA256SUMS`; the notices embed those exact locations;
and no application binary is reachable from the source location.

The committed receipt uses JSON schema 1 with exactly `schema`, `method`
(`anonymous-https-get`), `location`, `fetched_at_utc` (UTC `Z`), and `files`.
Each file has exactly `url`, `sha256`, `size`, and `http_status` (`200`). The
inventory's `materials` list has the same URL/digest/size tuples. No cookie,
authorization header, redirect token or private document belongs in this
public evidence. The actual fetch procedure and network observation remain
part of the reviewer record; receipt structure alone is not anonymous access
proof. See [the source-offer receipt contract](../planning/downstream/source-offer-receipt-gate-2026-11-08.md).

## Local source-review packages — 3 November 2026

Both source families now have local review archives. D2's existing verified
37-file package contains the source/npm inputs, patch and 16 Go module ZIPs; see
[its manifest and controls](evidence/d2-0.1.33/README.md). The Graphviz assembler
`tools/prepare_graphviz_offer.py` now packages the exact Graphviz/Viz/Expat/npm
inputs, current notices/SBOM snapshot, build evidence and explicit review limits.
[Its checkpoint](evidence/graphviz-source-review/README.md) records the manifest,
digest and reproduction. The assembler never executes upstream packages or tools.

These are prepared review objects, not approval as complete corresponding source.
Compiler/sysroot inputs and embedded runtime attribution still require review;
source-offer URLs/status stay planned. Rebuild the review snapshot if notices or
source inputs change, using a new local output name; the tool refuses to overwrite
a different archive. No website deployment, source-only public upload, application
binary publication or signing is performed by this preparation. The explicit
source-archive authorization above remains required for publication.

## 14 November candidate package update

The new D2 local package includes the original 37-file historical review
archive, the official 2.00.5 TTF and lossless WOFF, a narrow Chroma patch,
the controlled WASM/browser payload build record, a tested local Go module
proxy seeder, and scoped ELK/Java/Brotli source references and notices.
The new Graphviz package includes the finite 489-member link union, basename
source candidates and their source-file digests, plus a pinned Emscripten
source reference and exact compiler-image comparison for 402 candidate files.
These packages remain **review-only**: generated ELK and
decoder correspondence, Go JS runtime, Graphviz compiler-image/per-file
terms, Rough.js and Stack Overflow grants, and independent rights decisions
are still open. A model review of package integrity is not a legal opinion.
The final local package manifest, hashes, exact proposed public locations and
remaining approval gates are recorded separately under
`evidence/source-offers/` to avoid putting an archive's own hash inside it.
