# Recognize front matter with CommonMark line endings

Front matter must be detected consistently for LF, CRLF and CR documents.
The current SourceMap recognizes all three, but FrontMatterExtractor's line
records only stop at LF. A CR-only document therefore exposes its YAML as body
text and loses the correct body-line offset. Fix line recognition while keeping
original body bytes and the existing normalized YAML parser input policy.

## Baseline and boundaries

Baseline is PR72's stable source `48d5be77f6015d37af369719549682b32eee406e`,
based on main `a95ff1fc4498e925eb1582fa6eb9e7fab5baf5ad`. Require PR72's source
qualification/integration before merging this dependent unit. MostlyText #6/#11
own format/export fidelity; #17 consumes the evidence. This is a parser source
fix, not complete application/native fidelity acceptance.

Only the internal FrontMatter line-record helper, its inaccurate raw-value
comment and focused tests/evidence change. Keep original delimiter/BOM/trailing-
whitespace/blank-second-line/no-closer rules, Yams parsing, package pins,
serialized document bytes, public structures and consumer activation unchanged.
Existing CRLF tests intentionally require `raw` YAML text normalized to LF;
retain that test and behavior. Clarify that normalization concerns derived
parser input, never the user's authored file. Do not turn this into a save or
encoding rewrite.

## Algorithm and proof

Scan the existing UTF-16 view once for CR or LF, consuming CRLF as one ending.
Record original offsets including the complete ending and logical line numbers.
Keep a final empty record after a terminal ending, consistent with SourceMap.
Avoid a full-document UTF-16 array or repeated suffix scans. The extracted body
still slices the exact original source after the closing line's end offset.

First reproduce with an unchanged owned Foundation-only parser fixture, exact
pinned dependencies and new golden tests. Preserve baseline failures. Exercise
all three endings/mixed endings, BOM/emoji, `---`/`...`, empty front matter,
trailing delimiters and no-closer/blank-line rejection. Assert normalized YAML
values, exact original body/line offset, original coordinate slices and line
records against SourceMap. Run existing FrontMatter/parser/scanner tests and
new diagram goldens in Debug and Release; maintain all existing assertions.
Run pinned formatting/strict lint, Compliance/inventory and complete hosted
locked package/app/CLI/build checks. No local product/AppKit/WebKit execution.

## Completion

Review/merge the qualified exact source after PR72, verify actual tree/parents
and clean canonical fast-forward, update owning issue evidence and reassess all
open issues after each update. Do not close broad native/export/editor issues
from this parser component proof. Preserve all real CI failures, release/native
holds and strict release predicates. Stop on changed source offsets, parser-
policy disagreement or any need to weaken current CRLF/format-fidelity tests.
