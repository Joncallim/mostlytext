# Native math placement and font-context probes

## Owner summary

Before production uses the new accessible attachment wrapper, verify that it
preserves display placement and updates metrics when only the surrounding font
changes. These are component correctness requirements for #9/#7, not final
app/VoiceOver acceptance. Main abc3a5c8 contains merged PR88/PR89; this branch starts
from PR90's source f83d0dbb, whose shared reference API is stable but still awaits
complete hosted qualification. No local native/product/signing execution is allowed.

## Narrow questions and evidence

Textual's existing isMathBlock recognizes a concrete MathAttachment; the new opt-in
wrapper has another concrete type. Source review therefore predicts loss of display
classification. Add a native test against current immutable Textual ebf6590a FIRST:
base and wrapped display attachments must retain block classification; inline and
mixed content must not become blocks. Keep assertions identical when remediating.

TextFragment rebuilds TextBuilder when content changes or container geometry changes.
Its font environment is read separately. This suggests, but does not prove, stale
placeholder metrics when the font changes with fixed content/container. A synthetic
owned host compares an ordinary text control and opted-in inline equation at font
14 then 28. Require actual positive geometry/control setup, ordinary font-control
update and corresponding attachment geometry update. A missing/unchanged control
is a host failure; it is not evidence of a metric bug. Poll only the existing
50 x 10 ms; preserve depth 24 / 512 native node bounds and owned-window cleanup.

Copy all exact tests/support sources into the existing three-immutable-pin hosted
fixture. Run only the focused workflow for the baseline before opening a broad PR;
retain failures and native records. The full existing CI remains the merge gate.

## Remediation boundaries

If placement fails, narrowly teach the existing concrete-type classifier to see
through Textual's own accessibility wrapper, preserving legacy behavior and all
actual drawing/metrics/PNG. Avoid a new public wrapper taxonomy. Preserve original
and repeated opt-in descriptors; source IDs remain caller-owned.

If font metrics fail with a positively updated ordinary control, rebuild TextBuilder
on the relevant environment change. Do not alter glyph caches or font/resource
bytes to hide stale state. A passing baseline rejects that hypothesis and warrants
no renderer change. Any owner child receives a new immutable pin, exact patch,
unchanged-resource/pin proof and updated inventory/notices/SBOM. Native tests keep
all controls/assertions/bounds. Broader scalar-safe Preview transport and joint math
activation wait for these decisions and the parent contracts; no whole-issue
criterion closes from this component evidence alone.
