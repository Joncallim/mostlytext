# One immutable Markdown parse per ordinary export

## Owner outcome and baseline

Ordinary export must not parse the same source/options/revision twice. Reuse
the accepted immutable MarkdownDocument for contributions and composition while
keeping the distinct cmark serialization pass. This resolves a bounded #117
residual without enabling generated-link navigation. Baseline is destination
head 025b89f96f58063e522d7823e890c4cace1f057b (#569), after input-authority #568.
Master stays 15c0fae22f7618e94c82681227057c66011be2a9.

## Existing implementation and change

The ordinary coordinator parses for the contribution registry, discards the
parse and asks ExportComposer to parse again. The disabled validated route
already has FrozenExportParse with byte-exact source and revision binding.
Extract that cache into its own app source file and give it an immutable
effective MarkdownParseOptions field with the current default for old callers.
Different source bytes, revision or options reject; no silent fallback or
cross-operation cache is introduced. Keep cancellation checks. The cache is
actor-confined: ordinary composition consumes its stored document once and
releases that reference before cmark rendering, avoiding a new full-tree peak
memory lifetime. The disabled SVG fallback retains repeatable access by default.
Both modes transport the same immutable document value; neither changes source.

The contribution helper returns its adaptation and this frozen parser together.
HTML and PDF composition consume that same parser. No live document, theme,
grant or destination is read again. No dependency graph, persistence, editor,
raw-HTML policy, cmark pass, resource limit or native print path changes.

## Evidence and limits

Use real MarkdownEngine parsing in a private Foundation-only harness with the
already pinned official swift-markdown/Yams/cmark sources. Tests cover cache
hits, distinct canonical-equivalent UTF-8, revision/options mismatch and
cancellation. Source-identical tests and Release timings compare two fresh
parses with one fresh parse plus a validated reuse on ordinary and technical
approximately 1-MiB inputs. Record raw samples, source hashes and checksums;
these are parser-component measurements, not whole-app/keystroke/PDF latency.
The hosted ordinary snapshot test must now observe exactly one upstream parse
and preserve all original source/theme/options/revision/output assertions.

Run Debug/Release controls, strict lint/format, Compliance, local unsigned
compile-only app/tests and complete exact-head hosted CI before integration.
Retain first failures. Local app/app-target execution remains held. Native
TOC/navigation, full Export phase/memory calibration, independent final review,
Daybreak/signing/account and public promotion gates remain unchanged.
