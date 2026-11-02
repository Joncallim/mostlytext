# Conditional editor settings publication

## Owner summary

Apply a consented legacy editor proposal only while the saved destination still
matches the value the user reviewed. Preserve later edits and unreadable data,
then verify the exact saved result. This unit supplies the single-domain write
boundary for E17; it does not activate import, record completion or replace the
required durable transaction journal.

Baseline: integration `fdee161354050d19cbb91736eea04de9786b7bbc`, master
`15c0fae22f7618e94c82681227057c66011be2a9`. The branch additionally contains
the separate CLI endpoint transport from PR #554. No application startup calls
the new publication API.

## Storage and concurrency

`UserDefaultsAppSettingsStore` remains the MainActor owner of ordinary settings
edits. A new initializer binds a store to one validated, explicit persistent
domain and constructs the matching UserDefaults suite itself. Existing callers
using the generic injectable initializer retain their behavior and cannot use
the migration publication API. Never accept an unrelated public defaults object
and domain name that could read one domain but write another.

The explicitly bound store reads its own persistent domain for both ordinary
settings and migration evidence. Registered, global and argument defaults do
not establish saved presence. Invalid names, system domains and the original
MacDown domain (including case variants and prefixed aliases) are refused before
opening a suite. This is a guard against accidental source writes, not a new
production bundle identity.

Publication is synchronous on MainActor, without suspension between capture,
comparison, write and exact persistent-domain readback. An immutable proposal
has already validated selection, field replacement consent and preserved all
unselected fields. Desired bytes mean already applied; captured-before bytes
permit one write only if the supplied fresh source snapshot still matches;
anything else is a conflict. Failed readback is an error, never completion or a
reason to roll back over a later value. No primary value, backup, journal or
original-MacDown domain is deleted by this API.

MainActor serializes participating in-process writers; it cannot provide a
cross-process compare-and-swap or prove defaults-daemon disk durability.
E17 must durably prepare its restricted journal before invoking this boundary,
obtain a fresh source snapshot, record acknowledgements and recover using the
same before/desired/third-value rules. The current unit adds no journal,
first-run UI, production activation, font/theme import or native acceptance.

## Verification

Use only uniquely named synthetic preference suites. Test registered-only
fallbacks, actual saved bytes, selected replacements, ordinary edits after
planning, malformed/future/non-Data destinations, changed sources, idempotence,
wrong/unbound domains and failed readback. Run focused Debug and Release tests,
strict lint/format, Compliance and full hosted CI before merge. Synthetic
preferences are removed only by their owning fixture. No app or real legacy
domain is needed.
