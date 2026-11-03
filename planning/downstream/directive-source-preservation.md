# Preserve directive source and define the Preview/export contract

## Owner summary

The opt-in directive parser can drop every block after an unfinished @Name {
from Preview, even though the original text remains in the editor and Export.
Preserve ordinary Markdown output when directive parsing would omit visible
content. Keep the real opt-in structural parser, and explain its limited purpose
in Settings: directives affect outline/structure, not custom rendered callouts.
This resolves the source policy intersection in MostlyText #6/#11 without claiming
whole Preview/Export, native layout or release acceptance.

## Baseline and reconciliation

Main 760fdc8397bd900a983d87f0202ce54ec54d0957. The actual source-identical Foundation/
CryptoKit-only engine/PreviewBlock probe shows balanced directives preserve source,
while an unclosed @Note { keeps only its header and loses later body/headings.
Export's cmark path receives the full original body and has no directive renderer.
The setting is a genuine parser flag; deleting it or making it inert would undo
#53's source-model correction. Keep existing persisted keys and option identity.

## Behavior, ownership and failure policy

MarkdownEngine owns source-preserving parse fallback. Parse with the requested
options first. For directive-enabled results that omit nonblank source lines,
compare the ordinary CommonMark parse. If ordinary renderable blocks cover visible
lines missing from the directive result, use the complete ordinary block/heading
result instead. Keep the exact original body/front matter/source map/revision/
requested options/fingerprint. Known invisible reference definitions alone must
not disable valid directive structure. Source omissions may never be normalized
into new authored text. No merge of stale or differently parsed snapshots.

Only the opt-in path may need a second parse. Default parsing stays unchanged.
Use bounded linear line/range comparison, with LF/CRLF/CR, blank lines and Unicode
handled by the current SourceMap/markdownLines contract. No main-actor UI work,
network, file mutation, new dependency, changed budget or parser ownership policy.

Preview and Export intentionally present directive syntax as ordinary Markdown,
with no DocC/admonition-specific rendering. Preview retains its parsed block
segmentation; the option may change outline/block structure, not introduce special
callout semantics. Settings explains this, including unfinished-source fallback.
Add surrounding catalog copy using the existing localization pipeline; native
translation/layout review remains in #3. Do not change or hide authored source.

## Files, verification and completion

Allowed: MarkdownEngine coverage/fallback helper and tests; Preview/Export directive
contract tests; Settings explanatory copy and its existing catalog; current planning
and issue evidence. No app launch guard, dependency/pin, release, identity, output
filesystem authority or native consumer activation change. Existing ordinary HTML,
math/diagram, parser snapshot/heading and source-identity contracts remain binding.

First freeze failing-before regressions against exact old source. Cover balanced,
unclosed/nested directives, visible tail/headings, reference-only definitions,
front matter, Unicode, LF/CRLF/CR, option on/off, exact options/source identity and
existing export-body preservation. Run source-identical non-application tests in
Debug/Release with pinned dependencies. Run strict lint/pinned format, locked
compile-only Release and complete hosted app/package/Compliance checks. Never run
local product/UI tests on UID501. Required native, parity, PDF, budgets and final
string freeze remain open, but the deliberate block-directive source policy may
be checked off once the actual source/runtime controls and merge are qualified.
