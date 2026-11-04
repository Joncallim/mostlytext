# Website identity update deployed — 4 November 2026

The owner-approved website update is live at [mostlytext.app](https://mostlytext.app/).
Application, website-source and live-backlog links now point to the separate
MostlyText repositories. The FAQ states that MostlyText application source is
MIT licensed, retains MacDown copyright/attribution and still needs final release
artifact verification. Historical alpha downloads and the explicitly dated
roadmap remain intact.

This is website deployment evidence for [MostlyText #16](https://github.com/Joncallim/mostlytext/issues/16)
and the website portion of [#14](https://github.com/Joncallim/mostlytext/issues/14).
Native application, independent rights review, corresponding-source publication,
signing/update/installed-state and final release gates retain their own evidence.

## Approved source and activation

- Approved website commit: [`0d04102bff8ddf35a9cc81bdc502a16a5898f7a2`](https://github.com/Joncallim/mostlytext-site/commit/0d04102bff8ddf35a9cc81bdc502a16a5898f7a2).
- Fresh tests and the 19-page build pass. All 51 prepared asset sizes and SHA-256
  hashes reproduce the approved manifest.
- Existing Worker: `mostlytext`; new version `c6d1a000-7db7-4856-a725-87305fe75468`.
- Deployment `9fd6cc79-ac7b-4e34-bc1a-42ecae698df0` activated at
  **4 November 2026, 15:23:38 Singapore time** (`07:23:38 UTC`), with API readback
  assigning 100 percent to the new version. The dashboard reports Ready.
- Rollback version remains `0f5b3550-e91b-4e30-84a7-a4c5694edbb8`.

Twenty changed assets were uploaded; 31 unchanged assets were reused. The upload
completion receipt preceded version creation. The staged version was checked
before activation. Routing-module hash
`b16239c4beb1799a20c10fca6bc8236a9e0f897e11739936b39791749e09f44e`, the sole
`ASSETS` binding, compatibility date `2026-10-15`, standard usage and all asset
settings match the previous version. HTML handling remains auto-trailing-slash,
not-found handling remains none, direct asset serving remains enabled, worker-first
remains false and base path remains `/`. No domain, route, access or zone-security
setting was changed. Temporary upload authorization was neither written to source
nor saved in the evidence.

## Public readback

| Check | Observed result |
|---|---|
| Complete asset set | All 32 non-HTML assets match the approved sizes and SHA-256 hashes, including scripts, styles, fonts, images and brand files. |
| Prerendered pages | All 19 pages match the approved HTML after removal of exactly one Cloudflare-injected analytics beacon script. No other content difference is accepted. |
| Sitemap | All 19 page URLs are present. |
| `/roadmap?deployment=0d04102` | HTTP 307 to `/roadmap/?deployment=0d04102`; query preserved. |
| `/roadmap/` and `?stage=after-1` | HTTP 200; browser navigation selects the intended stage. |
| Missing page | HTTP 404. |
| Live links and FAQ | Browser readback shows MostlyText app/site/backlog destinations and the MIT/MacDown wording; historical alpha/release links remain historical. |
| Phone layout | At 390 × 844, home and roadmap have no horizontal overflow; menu navigation and stage switching work. Fonts and visible images load; desktop sizing is restored afterward. |

Raw HTML byte comparison initially failed because Cloudflare adds its analytics
beacon after serving the uploaded HTML. Raw mismatch evidence is retained. The
qualified comparison removes only that exact single beacon script, validates its
public site identifier and requires every remaining byte to match. It does not
strip arbitrary scripts, whitespace or application markup. No analytics/security
setting was changed to make the comparison pass.

A default Python no-redirect probe returned HTTP 403; separate curl checks return
the required status/Location, and the signed-in browser completes the navigation.
The failed probe is retained and is not reported as a passed attempt.

## Retained evidence and limits

Local evidence: `/Volumes/Fast SSD/CORTANA-Builds/website-brand-cutover-20261104`.
It contains approved manifests, build/test logs, upload receipt, staged/active
Cloudflare metadata, per-asset hashes, retained raw HTML, exact beacon-normalization
proof, route responses and desktop/phone screenshots. Useful entry points are
`live-verification-qualified.json`, `edge-html-qualification.log`,
`cloudflare-active.json`, `deployment-ready.png`, `live-faq.png` and `live-phone.png`.

This update does not publish a new app binary or corresponding-source archive,
change public release claims, or establish final application/license acceptance.
The 17 broad engineering issues remain open; this website checkpoint adds no
new issue checkbox and waives no remaining criterion.
