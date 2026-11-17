# JSON physical-line coordinates

## Owner summary

JSON documents with CR-only line endings parsed correctly, but the diagnostic
and outline line numbers treated the entire file as one line. The editor could
therefore point to the wrong row after an error or show wrong row spans in the
outline. Count CR, LF and CRLF as physical line breaks while retaining the
original UTF-16 offsets, parser acceptance, document bytes and formatter policy.

## Finding and repair

The source review started from main `174462a00509543b7cb2364c62d3766caca5520e`.
`JSONScanner` accepts CR as JSON whitespace but indexed only LF. Two new
production-parser tests supplied CR-only and mixed-break documents. Before the
repair, the invalid unit on physical line 3 was reported on line 1 or 2, and
CR-only outline children both appeared on line 1. The retained
[first-failure log](evidence/json-physical-lines-2026-11-18/first-failure.log)
(SHA-256 `6414d5b49d9d9d1515e973634459a8de3d7f7cedd72edc477c989f9f10252b67`)
records six failed expectations in 18 selected tests. The scanner source at
that point was Git blob `d9503054f8f7dd406cb03265ba08670ad1b9d3fe`.

The new index adds the position after a lone CR and after every LF. In a CRLF
pair it adds only the position after LF, so one pair remains one line. The
UTF-16 source ranges are not rewritten. `JSONFormatter` already normalizes
CR-only and mixed-break input to LF when formatting is explicitly requested;
its comment now states that policy without implying that CR is not a physical
line break.

## Verification and scope

- The unchanged test assertions pass after the repair: 18/18 focused Debug
  tests; the broader JSON selection passes 133/133 Debug and 133/133 optimized
  Release tests. The original CRLF and Unicode coordinate cases remain green.
- SwiftFormat and strict SwiftLint on changed Swift files and ordinary
  compliance pass locally. The repository's complete hosted CI remains
  required before merge. The first local formatting and lint violations were
  test layout/style issues and were corrected; no production rule or timing
  ceiling changed.
- This is one finding from the smaller JSONSupport path named in issue #8's
  orthogonal review. It does not complete that whole review, the final native
  matrix, issue #5, or the exact signed-artifact gate. No app GUI was launched
  from the owner account.
