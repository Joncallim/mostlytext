# mostlytext.app (retained historical draft)

> Current website work belongs in [Joncallim/mostlytext-site](https://github.com/Joncallim/mostlytext-site).
> This application-repository copy preserves the original draft and claims ledger.
> Its future-tense rename and implementation rows are historical; do not deploy
> this snapshot or treat it as the current site/release status. Current application
> gates are in [the acceptance ledger](../planning/ACCEPTANCE_STATUS.md).

**Owner summary.** This is the first draft of the public download site for
MostlyText 1.0: a home page with the download button, an open-source page that
will host the licence archive (#148 LC-09), and a privacy page. It is plain
HTML and CSS with no build step, no cookies, no analytics and no third-party
scripts or fonts, so the site itself makes no outside requests.

**Status: not deployed, and not to be deployed before E17 (#18).** The copy
describes the intended 1.0 release, and several statements are not true of
today's build. Every public claim must have release evidence before the site
goes live (`planning/RELEASE_HARDENING.md`). The claims ledger below is the
checklist.

Non-goals: no hosting, DNS or deployment is set up here, and the appcast
(Sparkle's update feed) is not created here. Both belong to E17.

## Layout

| Path | Purpose |
|---|---|
| `index.html` | Home and download. The button points at `https://github.com/Joncallim/mostlytext/releases/latest`, which works once the repository is renamed (#158) and the signed DMG is published (E17). |
| `opensource/index.html` | Licence, notices and the per-release compliance archive (LC-09). The archive layout is in `compliance/ARCHIVE_PLAN.md`. |
| `privacy/index.html` | What the app and site send over the network. |
| `assets/site.css` | The only stylesheet. Light and dark follow the system setting. |
| `assets/mostlytext-lockup.svg`, `favicon.svg` | Copied from the frozen brand outlines in `design/brand/slant/production/out/` (D-029), single colour. |

Brand use follows `design/DECISIONS.md`: single-colour lockup, and no parallel
stripes or red-and-blue scheme (D-016). The site makes no trademark claim and
uses no "®" (D-031).

## Claims ledger

Each statement must be backed by the named evidence before deployment. If the
evidence can't be produced, change or remove the statement.

| Claim (page) | Evidence required before deployment | Status |
|---|---|---|
| Version 1.0.0; requires macOS 26 or later (home) | Release candidate `CFBundleShortVersionString` and `LSMinimumSystemVersion` | unverified |
| Signed and notarised by Apple (home) | `codesign --verify`, `spctl --assess` and the notarisation ticket for the published DMG (Mac, E17) | unverified: the Mac tranche (`planning/MAC_SIGNING_BRIEF.md`) proves the pipeline; the published DMG is checked at E17 |
| Opening, editing, preview, math, diagrams and export work offline (home, privacy) | The RELEASE_HARDENING §1.1 offline run on the release candidate | unverified |
| Documents aren't sent to any service (home, privacy) | Same offline run, plus a network capture during normal use | unverified |
| Markdown stays plain text on disk (home) | RELEASE_HARDENING §1.2 evidence | unverified |
| MIT licensed; descends from MacDown (home, open source) | `LICENSE` after the #158 header update (LC-10) | unverified until #158 |
| Notices ship in the app under About → Open Source Licences (open source) | LC-08 screen in the release candidate, and `compliance.py check --release --artifact` passing | blocked on LC-08 |
| Corresponding source for Graphviz and D2 (open source) | LC-02, LC-03 and LC-09 packages published and downloaded anonymously, with digests matching the inventory | blocked on LC-02/03/09 |
| Update checks go to mostlytext.app, send only app and macOS version, and can be turned off (privacy) | E17's Sparkle integration: appcast URL, request contents, and a Settings toggle | blocked on E17 (Sparkle isn't integrated yet) |
| No analytics, tracking or advertising code (privacy) | The release SBOM (`compliance/generated/sbom.cdx.json`) and a review of the release candidate's linked frameworks | unverified |
| The site uses no cookies, analytics or third-party scripts (privacy) | Inspect the deployed pages and the host's settings | unverified until hosting is chosen |

## Hosting (decided at E17)

Recommended default, subject to E17's architecture pass: serve this directory
with GitHub Pages under the `mostlytext.app` custom domain, and attach large
compliance source packages to the matching GitHub Release, linked from the
archive pages. That keeps everything in the one repository and account that
already hold the release, with no new vendor or credentials. The appcast
location defaults to `https://mostlytext.app/appcast.xml`
(`planning/RELEASE_PATH.md` §4).

## Preview locally

```sh
python3 -m http.server --directory website 8000
# then open http://localhost:8000
```
