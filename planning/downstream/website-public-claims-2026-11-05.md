# Public website claims corrected and verified — 5 November 2026

The live technical-work page now says that Preview and export have different
presentation paths and that parity, responsiveness and native release checks
remain open. It previously asserted a shared renderer/export equality and
unqualified typing responsiveness without the required evidence. The correction
aligns public copy with the source-only testing alpha and the remaining backlog.

All 19 website pages were reviewed. The roadmap is explicitly dated 15 October
and distinguishes merged development work from release verification. Performance
numbers under “How it will be checked” describe acceptance targets. Future work
is labeled planned/exploring. The application README and installation guide also
state the source-only status and outstanding native/performance/migration gates.
The current public-copy criterion in [MostlyText #4](https://github.com/Joncallim/mostlytext/issues/4)
is checked; new release notes, screenshots, changed public copy and exact-RC
claims must be checked again before promotion.

## Approved source and deployment

- [Website PR7](https://github.com/Joncallim/mostlytext-site/pull/7) merged as
  `b354a6b7ddd9342baf8357d38877612c659eb8df`, tree
  `9db70da06ada93d89b46568963818fb755547ddd`, exactly matching its reviewed head.
  Only the technical-work explanation paragraph changed.
- Clean merged-source tests and all 19 server-rendered pages build successfully.
  All 51 merged-source file hashes reproduce the pre-merge qualified build.
- The owner explicitly approved this deployment and named static archive.
  `mostlytext-site-b354a6b7-static-assets.zip` has SHA-256
  `f327793585d28ea4ffc1f5cad83fbfb4439c6fe07b183fd3da498328628f9437`.
- Existing Worker `mostlytext` staged version
  `c111e704-e28d-4b25-ac0a-d10b28832e1c` before activation. Deployment
  `1bc3ed27-3dad-4fcb-bc6d-2bcc1ca621d7` activated it at 100 percent at
  `2026-11-05T01:28:06.601736Z` (09:28:06 Singapore time).
- Previous version `c6d1a000-7db7-4856-a725-87305fe75468` remains available for
  rollback. Fresh active-version and settings readback confirm the new version.

All 51 assets were uploaded in three API-requested buckets; statuses 202, 202
and 201 yielded the completion receipt before version creation. Only the scoped
one-hour upload/completion authorizations were used in memory; they were not
saved in source/evidence and were cleared after use.

The Worker script etag remains
`b16239c4beb1799a20c10fca6bc8236a9e0f897e11739936b39791749e09f44e`.
Its sole ASSETS binding, compatibility date `2026-10-15`, standard usage and asset
configuration are unchanged: auto-trailing-slash, not-found none, direct serving
true, worker-first false and base path `/`. The staged resources were compared
before activation. No route/domain, zone-security or analytics setting changed;
historical source/archive/download routes remain handled by the unchanged module.

## Live verification

| Check | Observed result |
|---|---|
| Complete approved asset set | All 51 served sizes and SHA-256 hashes match the clean build's raw bytes: 32 non-HTML assets and 19 HTML pages. No normalization is needed for this curl readback. |
| Public correction | Normal browser readback shows the separate presentation paths and explicit open parity/responsiveness/native checks; the unsupported export-equality sentence is absent. |
| Sitemap | All 19 page URLs are present. |
| `/roadmap?deployment=b354a6b7` | HTTP 307 to `/roadmap/?deployment=b354a6b7`; query preserved. |
| Roadmap and stage-query routes | HTTP 200. |
| Missing deployment-check URL | HTTP 404. |
| Mobile home and corrected page | 390 × 844 viewport, document width 390; no horizontal overflow. Images decode and fonts load; desktop viewport restored. |
| FAQ/history | MIT/MacDown and open final-artifact wording remain; historical alpha-source link remains at its original release. |

The browser reports one refused connection to Cloudflare's external analytics
beacon. Application/site assets load; no analytics setting was changed to hide
that error. A reused older verifier initially required an injected beacon even
when the raw HTML already matched. That diagnostic assumption failed; the
qualification now prefers exact raw-byte identity, permitting only the previously
identified single beacon when raw bytes actually differ. The final receipt
records 19 raw matches, zero beacon-normalized pages. It never strips arbitrary
scripts, whitespace or markup.

## Evidence and boundaries

Retained local evidence is under
`/Volumes/Fast SSD/CORTANA-Builds/public-claims-review-20261105`: clean build/test
logs, approved archive and per-file manifest, upload receipt, pre/staged/active
metadata, all served HTML and `live-verification-qualified.json`.
Browser screenshots/readbacks are retained in the working session's
`output/playwright` folder. The prior [identity deployment receipt](website-brand-deployment-2026-11-04.md)
remains historical evidence, superseded only for the active website version.

This website deployment is explicitly authorized. It does not publish an app,
corresponding-source offer or release candidate, resolve independent attribution
review, establish native application behavior, or waive signing/update/installed-
state and exact-artifact gates. The current audit has 17 open whole issues and
178 unchecked original criteria; no whole issue is complete.
