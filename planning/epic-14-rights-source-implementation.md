# Issue 14 rights and source remediation

## Owner summary

MostlyText bundles several diagram engines and their nested code. This pass makes their attribution and source packages match the code actually shipped. It keeps the renderers offline and retains the current dependency versions except for the narrowly rebuilt D2 payload needed to replace the embedded font. Historical evidence remains intact. Unresolved permissions, publication, the signed candidate, and legal interpretation stay explicit release gates.

## Baseline and reconciliation

The implementation baseline is `07f9f6d1277d17aff1699116cada35c8eb7ef09d` on 14 November 2026. Ordinary compliance passes; strict compliance has six findings: two planned source locations and four aggregate independent-review entries. The 70 MiB D2 archive at `d2-source-review-bundle.tar.gz` passes its pinned verifier, but it omits identified ELK and JavaScript Brotli coverage and predates the proposed font replacement. The 58-member Graphviz archive with SHA-256 `e9db382f36e79f5153c1c31a32700084327ea735fb51dd811293116d648923ca` is historical; current assembler output differs, so a newly named package is required. The D2 notice calls the minified browser file readable corresponding source; that overstates what it contains.

The issue's checked technical parser classifications remain intact. None grants third-party permissions. Source-offer status remains `planned` until separately authorized public publication and anonymous retrieval. The Apple account agreement and binary signing are outside this pass.

## User journeys and invariants

- A user can render Mermaid, D2, and Graphviz locally in preview and export without a network dependency.
- A recipient can read the bundled notices and, after separately authorized publication, obtain a version-matched preferred-source package for each required offer.
- If provenance or permission cannot be established, the release gate remains open with an exact question; no checker exception or silent omission converts uncertainty into a pass.
- Preserve old receipts and shipped-version correspondence. New D2 bytes require a new controlled build record and affected rendering checks. Notice-only changes do not alter renderer resources.

## Ownership and data flow

`compliance/inventory.json` is the canonical component graph. `compliance/licenses/` holds complete selected texts. `compliance/tools/compliance.py` generates the notices and SBOM included by the app. `compliance/evidence/` records source-to-bundle correspondence and review limits. `compliance/tools/prepare_*_offer.py` builds local source packages from pinned input archives. The Swift renderer targets own the runtime resources; this pass does not change their public interfaces, concurrency or cancellation contracts.

Source inputs and hashes → scoped provenance and component records → generated notices/SBOM → deterministic local source archives → ordinary/strict compliance and app resource verification. The strict checker remains unchanged.

## Slices and stop conditions

1. Verify retained archives and capture each newly reported borrowed snippet against actual source/map bytes. Stop a claim if the cited reference does not match the retained code.
2. Add supported scoped notices and provenance for the Framer/Velocity, ELK, JavaScript Brotli, Go runtime, JamaJS and other confirmed nested contributions. Preserve unresolved grants as review entries.
3. Convert the official Liberation Mono 2.00.5 regular TTF without altering any sfnt table, patch only Chroma's embedded source, and build D2 with pinned Go inputs. Stop if conversion, source correspondence, or representative behavior cannot be demonstrated.
4. Review the finite Graphviz link-input union, direct objects and generated/runtime inputs. Include conservative applicable notices where exact retained-code proof is unavailable. Prepare new D2 and Graphviz archives with manifests, hashes and explicit limits.
5. Regenerate notices and SBOM, run the full compliance suite, ordinary and strict checks, affected renderer/export/offline checks, and have a separate reviewer inspect the integrated source coverage. Submit a PR and record immutable evidence on issue 14. Audit issues after each issue mutation.

## Failure, trust and performance model

All upstream archives and generated bundles are untrusted inputs to bounded offline verification. Packaging rejects unsafe paths and mismatched hashes. No upstream build/publish script is executed. The app remains offline. D2's controlled rebuild must compare compressed size and representative render latency with the existing payload; materially worse output is reported rather than silently shipped. A missing source revision, grant, or complete generated-code input remains an explicit open item. No application binary or source package is published by local preparation.

## Verification

Run `python3 -m unittest discover -s compliance/tests`, `python3 compliance/tools/compliance.py check`, and `python3 compliance/tools/compliance.py check --release`; inspect generated notices/SBOM and source archives, run focused renderer tests and a pinned Release app build for any resource change. Strict failures requiring public source, independent rights approval, or the exact signed artifact are expected until those gates are actually complete.
