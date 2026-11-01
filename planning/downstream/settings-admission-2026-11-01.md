# Settings admission and legacy-plan reconciliation

## Owner summary

Keep persisted preferences intact when this build cannot interpret them, and
give startup and the future importer the same evidence about stored editor
values. Reconcile the existing private eight-commit #53 unit onto integration
`9de81f5f` without importing its unrelated renderer/export/save branches.
Legacy consent, application, journaling and native migration remain separate.

## Exact numeric and structural admission

The reconciled editor decoder retains JSON number spellings, but converts the
schema version to Double before deciding whether it is an integer. A decimal
fraction close enough to 1 can round into the supported version. Other normal
settings domains still use JSONSerialization, which also discards duplicate
members and lexical precision. Admitting those bytes authorizes an ordinary
whole-domain save, so this is a preservation boundary rather than cosmetic
classification.

AppSettings will share one bounded read-only JSON object admission helper using
its already-declared JSONSupport dependency. Reject invalid UTF-8, input over
1 MiB, parser-invalid/duplicate members and canonically colliding root keys.
Keep the existing domain allowlists, required fields, additive defaults and
typed range validation. Classify declared schema numbers from decimal digits
and exponent exactly: supported positive integer 1; larger positive integers
future; fractional, nonpositive and wrong-type values malformed. Never use a
floating-point approximation as authority to rewrite a schema.

This deliberately replaces the historical test that accommodated Foundation's
rounded NSNumber value for two fractional literals. That accommodation was a
parser limitation, not evidence that those fractions are schema 1. The new raw
parser makes the stronger preservation rule enforceable; the revised regression
requires the unreadable primary bytes to survive an ordinary save. The first
combined run retains the four expectation failures from that historical test.

Startup, ordinary save protection and editor import evidence use that shared
gate. No original MacDown domain is read, no importer is activated, no new
dependency is added and no multi-key transaction is claimed. Tests use only
synthetic raw bytes and unique disposable defaults suites. Capture the failing
precision regression first, then cover equivalent integer spellings, extreme
exponents, duplicates and unchanged raw values across all five domains.
