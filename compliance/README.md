# Third-party licence and provenance gate

**Owner summary.** MostlyText ships under MIT, and bundles third-party components and separately credited embedded code: parsers, a Markdown library, diagram engines compiled
to JavaScript and WebAssembly, math fonts, and colour themes. Each keeps its
own licence, and some licences (Graphviz's EPL-2.0, D2's MPL-2.0) also require
the source to be available. This directory is the release gate for those
obligations (MostlyText #14, formerly #148; LC-01 to LC-10):

- `inventory.json` lists every third-party component the app ships, where it
  came from (exact upstream revision), its licence and the files it owns.
- `tools/compliance.py` checks that list against the source tree, generates
  the notices file and a software bill of materials (SBOM), and, at release
  time, refuses to pass while anything is pending or unverified.
- `generated/` holds the generated `THIRD_PARTY_NOTICES.md` and
  `sbom.cdx.json`. The implemented Open Source Licenses window (LC-08) reads
  the bundled canonical notice file as native plain text. Its real-app keyboard,
  accessibility and localization acceptance remains separate.

Why this way: the notices have to match what actually ships, byte for byte.
A single machine-checked inventory catches a new library, a changed file or a
deleted licence text in CI, instead of in a manual audit before release.

Risks and limits: this is evidence gathering, not legal advice, and no legal
clearance is claimed. The exact SwiftPM revisions are proved by the committed
lock file (`MacDown2/Packages/MacDownKit/Package.resolved`, LC-05, #165), which
this check enforces against the inventory. Two things can't be proved from this
repository alone: the runtime resources inside the final signed app (checked
on a Mac with `--artifact`; compiled code can't be checked this way, see below),
and public source availability (checked when LC-09 hosting
exists). Those stay **unverified**, never passed, until they are checked.

Non-goals: this doesn't change the app, its dependencies or the lock file,
and it doesn't publish anything.

## Commands

Run from the repository root. They need only Python 3.11 or later.

| Task | Command |
|---|---|
| Check the inventory against the tree | `python3 compliance/tools/compliance.py check` |
| Show everything still blocking public 1.0 | `python3 compliance/tools/compliance.py check --release` |
| Check a built app or mounted DMG (Mac; the signing script runs this) | `python3 compliance/tools/compliance.py check --release --artifact /path/MostlyText.app` |
| Regenerate the notices file | `python3 compliance/tools/compliance.py notices` |
| Regenerate the SBOM | `python3 compliance/tools/compliance.py sbom` |
| Run the tool's own tests | `python3 -m unittest discover -s compliance/tests` |

The `Compliance` workflow runs the tests and the tree check on every pull
request and push to `main`. It also prints the release ledger for
information; that step is expected to fail until the release candidate
exists. The strict version runs in the signing script's
`--release-candidate` mode, against the built app.

`xcodegen generate` creates `MacDown2/MacDown2/Info.plist` from the app
properties in `MacDown2/project.yml`. That exact path is registered as
first-party metadata because Xcode processes it into the app. It is not
excluded as undistributed content. Other property-list files still need
inventory ownership; Git ignore rules do not exempt them from the check.

## What the check rejects

| Rule | Tree check | `--release` |
|---|---|---|
| A file under `MacDown2/` that is neither first-party nor owned by a component | fail | fail |
| A file inside a component's wildcard-owned boundary (such as a vendored package's `**`) that isn't in that component's audited `files`, licence texts or runtime resources. `owns` says which component a file belongs to; it doesn't make the file compliant, and such a file can't pass as first-party | fail | fail |
| A `project.yml` package requirement (`exactVersion`, `from`, `minorVersion`, `branch`, `revision`…) that differs from the inventory, or a `packages:` entry the checker can't read (it fails closed) | fail | fail |
| A SwiftPM dependency not in the inventory, in any `Package.swift` under `MacDown2/` (found automatically) or in `project.yml`'s `packages:` | fail | fail |
| A local package that no component owns, or an XcodeGen local package outside `MacDown2/` | fail | fail |
| A `.package(...)` declaration the checker can't read, such as a registry `id:` or an interpolated URL (it fails closed) | fail | fail |
| A manifest requirement that differs from the inventory (stale mapping) | fail | fail |
| A missing or edited licence/notice text, or a vendored file whose digest changed | fail | fail |
| A runtime resource whose recorded digest no longer matches its source file, or a vendored bundle with no runtime resources declared | fail | fail |
| A copyleft component with no source location recorded | fail | fail |
| Generated notices or SBOM out of date with the inventory | fail | fail |
| No lock file, an unregistered resolved package, a registered package missing from the lock, or a resolved revision that differs from the inventory (`lockfile_enforced` is `true`) | fail | fail |
| A component still `pending`, or with open items | allowed | fail |
| A source location not yet verified by anonymous download | allowed | fail |

Manifests are read by a small comment-aware scanner, not a Swift parser. It
handles single-line and multi-line `.package(...)` declarations, ignores
commented-out ones, and extracts `exact:`, `from:`, `branch:` and `revision:`
requirements, noting `.upToNextMinor/Major`. A range requirement (`"1.0"..<"2.0"`)
is kept verbatim so it can't silently match a recorded one.

## What `--artifact` proves about a built app

The inventory separates two records:
- **`files`** is provenance: the source-tree files a component owns, with
  their digests.
- **`runtime_resources`** is the must-ship contract: files that must appear
  in the built `.app`, identified by name and SHA-256.

With `--artifact`, the check fails if any of these is true:

1. A runtime resource is missing from the app, or its bytes differ. The
   resources are the Mermaid, Viz.js and D2 engines, both themes, every
   tree-sitter query file that ships (the vendored grammars' files, plus the
   `queries/` folders that the remote grammar packages copy into the app,
   matched against their upstream digests), and all 12 SwiftUIMath fonts,
   also matched against their upstream digests.
2. The app doesn't contain this repository's `LICENSE` and generated
   `THIRD_PARTY_NOTICES.md`, byte for byte.
3. The app ships a script, WebAssembly, font or tree-sitter query (`.scm`) file (the extensions listed in
   `inventory.json` → `artifact.registered_extensions`) whose digest isn't a
   known runtime resource or a first-party source file.

The artifact walker also rejects escaping, absolute, dangling or cyclic symbolic
links, special filesystem objects, and unreadable directories/files. Relative
links must resolve entirely within the prepared artifact, with at most 40 link
hops; directory aliases are validated without a second traversal. Internal file
aliases are checked under their distributed name, so a .js alias cannot hide
unregistered bytes stored in a .txt file. Versioned framework links remain valid.
The only external-link exception is the exact root Applications -> /Applications
installation shortcut outside an app bundle; it is never traversed or hashed.

Provide a stable prepared/signed directory. This is not a race-free filesystem
snapshot or a code-signature check. A root supplied through a filesystem alias
is resolved once before inspection. Required resource bytes, source/publication
obligations and the exact signed-candidate gates remain unchanged.

It does **not** prove anything about compiled code. Swift packages and the C
grammar parsers are linked into the binary and can't be matched by digest.
For those, the evidence is the source-tree check, the exact revisions in the
SBOM and the enforced lock file. Data files that dependencies
copy in with extensions outside that list (for example SwiftUIMath's font
`.plist` metrics) are covered by the notices but aren't matched individually.

The Compliance workflow runs on every pull request and every push to
`main`, with no path filter. A test (`test_compliance_workflow_cannot_be_skipped_by_path_filters`)
fails if anyone narrows it.

The tests in `tests/test_compliance.py` break a passing fixture one way at a
time and assert that each break fails, including:
- an unregistered multi-line dependency;
- an unowned local package;
- a new nested manifest;
- an XcodeGen package;
- a missing or modified runtime resource;
- a stray font in the app;
- missing or stale notices;
- stale digests and mappings.

`tests/test_release_script.py` runs the signing script against stub Apple
tools. It proves that `--dry-run` records a failing licence gate or a missing
notarisation log as UNVERIFIED, and that `--release-candidate` stops on
either.

## When you change a dependency or bundled file

1. Update the component in `inventory.json`: version, full revision, digests,
   and the licence texts. Take licence texts verbatim from the upstream
   revision and put them in `licenses/` as `<component-id>--<FILE>.txt`,
   recording the upstream path, revision and SHA-256.
2. Run `notices` and `sbom`, then `check`.
3. Commit the inventory, the licence texts and `generated/` together.

**The lock file is enforced** (`"lockfile_enforced": true`). A dependency
update that changes `MacDown2/Packages/MacDownKit/Package.resolved` must update
the matching components in the same change: the new revision, the licence
text re-checked at that revision, and any newly resolved package registered.
Otherwise CI fails.

## Provenance findings (2026-09-28)

Method: compare the Git blob hash or SHA-256 of each shipped file with the
upstream history or the published npm tarball. Nothing below was inferred from
file names or comments alone.

| Item | LC | Finding |
|---|---|---|
| TreeSitterMarkdown (vendored) | LC-04 | The block/inline parsers, headers, injection queries and inline scanner match `tree-sitter-grammars/tree-sitter-markdown` **v0.5.3** (`f969cd3`). The block scanner additionally backports exact upstream safety commit `38dc6f5`; the package README records its full revision and content digest. MIT, © 2021 Matthias Deiml. The package had no licence file: `LICENSE` is now copied verbatim from that tag, and `README.md` records the evidence. The two `highlights.scm` files are local rewrites for this app's capture names. Upstream says those queries came from nvim-treesitter, so its Apache-2.0 notice is carried as well, conservatively. |
| TreeSitterJavaScript (vendored) | LC-01 | Byte-identical to `tree-sitter-javascript` **v0.25.0** (`44c892e`). No local changes. |
| TreeSitterSQL (vendored) | LC-01 | Byte-identical to upstream's generated-source deploy `851e9cb` (`gh-pages`), built from `main` `3c99273` (after v0.3.11). No local changes. The package README that `Package.swift` referred to didn't exist; it does now. |
| Tomorrow Dark theme | LC-06 | Chris Kempson's Tomorrow **Night Eighties** palette (MIT), by way of MacDown's legacy `Tomorrow.style` (MIT), including MacDown's `#888888` comment colour. Attribution added for both. |
| "Tomorrow Light" theme | LC-06 | **Not derived from Tomorrow.** Its seven token colours all come from GitHub's `github-syntax-light` v0.4.1 palette (MIT, © 2016 GitHub, Inc.); the text, caret and selection colours are local choices. The licence is fine and attribution is added. The misleading name belongs to E23 (#113), which owns theme integration and will decide whether to rename or re-source the theme. |
| Mermaid, Viz.js | LC-01, LC-02 | `mermaid.min.js` and `viz-global.js` are byte-identical to the npm releases mermaid@11.17.2 and @viz-js/viz@3.30.0. The viz bundle reports Graphviz 16.0.0. |
| D2 | LC-03 | Identical to npm @terrastruct/d2@0.1.33 except the one documented export statement. The existing `NOTICE.txt` is accurate. |
| SwiftUIMath fonts | LC-01 | New finding: SwiftUIMath ships 12 OpenType math fonts under the SIL Open Font License 1.1 and the GUST Font License. Their licence texts and each font's own copyright line (read from its `name` table) are now in the notices. |
| libyaml in Yams | LC-01 | New finding: Yams ships libyaml's C sources without libyaml's licence file. The libyaml MIT notice is added. |

Open items per component are listed in `inventory.json` and by
`check --release`. The main ones: Mermaid's bundled npm dependencies, the Graphviz and D2 corresponding-source
packages (LC-02, LC-03 and LC-09), and confirming the font set in the signed
app.

## Current nested notice distribution — 3 November 2026

The [Mermaid package checkpoint](evidence/mermaid-package-notices/README.md)
distributes the complete selected texts for all 74 mapped package records,
including the separately retained Cytoscape own-code notice. Two records remain
content-matched references with unresolved original versions; neither is encoded
as an exact npm component. DOMPurify uses the captured Apache-2.0 option.
[Source-build attributions](evidence/nested-build-attribution/README.md) additionally
cover four Rough.js dependency inputs, 16 D2 module inputs and two
Graphviz parser/compiler references. Exact source-build
lineage is not independent proof of all binary-retained code or a complete
embedded-code audit. The strict Mermaid, D2 and Graphviz items remain open.

Ordinary offline CI checks the committed projections and every distributed text;
raw-input replay additionally validates the captured archives and source links.
The current blockers and source-publication boundary are recorded in
[RELEASE_PREPARATION.md](RELEASE_PREPARATION.md). Dated evidence directories retain
their original outcomes and limits; later scoped updates do not rewrite history.
