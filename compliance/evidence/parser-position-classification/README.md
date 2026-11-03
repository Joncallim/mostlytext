# Syntax classification of parser review positions — 4 November 2026

The actual JavaScript syntax accounts for **3,428 of the original 3,528 remaining
references**. Another **100 remain technically unclassified**. Every original
position retains its independent attribution/rights-review requirement. These
categories do not assign copyright, prove semantic reachability, identify earlier
compiler/input versions or clear the complete Mermaid audit.

The [compact receipt](classification.json) binds each of the 2,597 distinct original
positions to its exact original row index and SHA256. Hashes use UTF-8 JSON with
sorted keys and no insignificant whitespace. Original rows retain member/digest,
one-based UTF-16 coordinates and every linked outer generated coordinate in
[the unchanged original index](../esbuild-parser-runtime/review-positions.json).
No source text is copied into this receipt. All members also bind to the
[complete 192-member reproduction](../parser-runtime-reproduction/README.md) and
unchanged shipped Mermaid bytes through the offline guard.

| Actual syntax | Outer references |
|---|---:|
| Import declaration | 346 |
| Namespace export bindings | 1,647 |
| Name-retention call in a static class block | 524 |
| Punctuation-only syntax line | 911 |
| Still unclassified | 100 |

[The portable recipe](classify.mjs) uses the integrity-verified Acorn 8.19.0
JavaScript parser under pinned Node 24.16.0. [Tool provenance](tool-proof.json)
records the official archive's SHA512 integrity, SHA256 and module digest. The
parser runs only in owned audit fixtures; it is not installed by CI or distributed
in the app. Offline CI uses Python's standard library and the pinned packet.

Namespace properties must be noncomputed identifier keys with zero-argument
arrows returning identifiers. Name calls must be the sole statement in a static
class block, with this and an identifier-shaped literal name. Punctuation lines
require actual punctuation tokens: template-string and comment contents cannot
qualify merely because their text looks like closing braces. These are syntax
facts, not an ownership inference from a compiler's output.

Eleven actual parser controls include executable getter/name-call mutations,
additional statements, template/comment lookalikes and supplementary Unicode
coordinates. A zero-width EOF token was initially counted as source content and
refused the positive punctuation control; excluding tokens with no characters
fixes that handling without weakening the control. The initial failed run is
retained locally. [Actual input controls](actual-controls.json) reject a changed
published member and changed original index before producing a receipt; restoring
the member reproduces the exact receipt bytes.

## Replay

Use an owned copy of the integrity-verified Acorn module and exact parser archive
members, preserving dist/ member paths. From the repository root:

```sh
/path/to/node24 compliance/evidence/parser-position-classification/classify.mjs \
  /path/to/verified/acorn.mjs \
  76254fc76529713b4dfd2532972d17a991ffd9aafeebb1f977445b5506b9fb0b \
  compliance/evidence/esbuild-parser-runtime/review-positions.json \
  /path/to/parser-members /tmp/parser-classification.json
cmp compliance/evidence/parser-position-classification/classification.json \
  /tmp/parser-classification.json
python3 compliance/tools/verify_parser_classification.py
python3 -m unittest discover -s compliance/tests
```

[The manifest](manifest.json) binds the recipe, receipt, tool proof, actual controls,
original index and parent reproduction. The verifier refuses missing/duplicate/
reordered rows, changed coordinates/member/outer references, unsupported categories,
false clearance and inconsistent totals. It does not rerun Node in CI or replace
independent review. Original source-map/index reports, all notice/SBOM/runtime/pin
bytes and six strict release failures remain unchanged. Remaining origin/grant,
nested-code/source/runtime/font, publication, native and exact signed-artifact
requirements stay open in MostlyText #14 and its review packet.
