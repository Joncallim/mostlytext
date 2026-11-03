# Exact disposition of the final 100 parser positions — 4 November 2026

All **100 references left by the first syntax audit now have a specific technical
disposition**. They occur in one exact reproduced parser chunk. The combined later
set has no technically unclassified reference; every original independent
attribution/rights-review requirement remains. This does not clear licences,
infer ownership, identify earlier compiler/input versions or prove reachability.

| Actual structure | References |
|---|---:|
| Constructor super spread-forwarding | 44 |
| Uninitialized var declaration | 10 |
| Closing object delimiter | 10 |
| Closing array delimiter | 7 |
| Else-if keyword | 15 |
| Alternate-block closing boundary | 3 |
| Invoked zero-argument arrow header | 2 |
| Wrapper strict directive | 1 |
| Numeric module-table header | 6 |
| Static class-block opening | 2 |

[The receipt](classification.json) selects exactly the 100 previously unclassified
rows of [the first audit](../parser-position-classification/README.md). It preserves
each original index/hash and previous category; its separate category records this
later disposition. Exact token and supporting-node UTF-16 spans and SHA256 hashes
make the findings inspectable without copying third-party source text. The chunk
is dist/chunks/mermaid-parser.core/chunk-FOHPRMQF.mjs, SHA256
5c83305b04a62463567bdf6d82d9ba9dfc3795e516d8cc848e6981504af48068.
The original source-map report/index, first audit and complete 192-member
reproduction remain unchanged.

[The portable recipe](classify.mjs) parses the actual copied member with the same
integrity-verified Acorn 8.19.0 under Node 24.16.0. [The parent tool proof](../parser-position-classification/tool-proof.json)
records its official archive/module identity. CI installs neither Node nor Acorn;
it uses the pinned receipt and standard-library Python verifier.

## Narrow admission and actual controls

Constructor forwarding requires an actual constructor with no parameters and
exactly super(...arguments) at the selected call. Initialized declarations do not
qualify as uninitialized bindings. Delimiters must be real final object/array
syntax tokens; branch boundaries must have the actual parent/alternate role.
Wrapper and module-table labels stop at their headers, excluding executable
bodies and later bindings. A static keyword requires an actual StaticBlock node.
These syntax facts do not imply that the compiler owns the surrounding code.

Twenty-seven actual parser controls reject changed constructor arguments, initialized
declarations, template/comment/string lookalikes, non-wrapper or executable-body
probes, later cache bindings and false static syntax. Supplementary Unicode proves
UTF-16 positioning. Initial controls revealed that an outer grouping parenthesis
is outside the arrow node and that the real module table shares a declaration with
a later cache binding. The corrected probes/header boundary retain negative
controls for both excluded regions; initial failed runs are preserved locally.

[Actual-input controls](actual-controls.json) refuse changed member, original index,
first receipt and parser-module bytes before output. Restoring the copied source
reproduces the exact receipt. [The manifest](manifest.json) binds this packet to
its original parent and reproduced member. Offline controls reject substituted,
missing/duplicate/reordered rows, changed coordinates/member/references, invalid
node/token evidence, changed totals and false clearance. A zero technical remainder
must never replace the independent review required by MostlyText #14.

## Replay

Use owned exact parser members and the verified Acorn module documented by the
parent packet. From the repository root:

```sh
/path/to/node24 compliance/evidence/parser-residual-positions/classify.mjs \
  /path/to/verified/acorn.mjs \
  compliance/evidence/esbuild-parser-runtime/review-positions.json \
  compliance/evidence/parser-position-classification/classification.json \
  /path/to/parser-members /tmp/parser-residuals.json
cmp compliance/evidence/parser-residual-positions/classification.json /tmp/parser-residuals.json
python3 compliance/tools/verify_parser_residuals.py
python3 -m unittest discover -s compliance/tests
```

App/runtime/pin/inventory/notice/SBOM/build inputs and all six strict release
findings remain unchanged. Remaining source/runtime/font review, origins/grants,
approved source publication/retrieval, native and exact signed-artifact acceptance
stay open. No application or upstream runtime is executed by this audit.
