# Export destination admission

## Owner outcome and baseline

An export must not overwrite a source/open document or silently adopt a
destination replaced while rendering. Retain the selected parent and exact
observed primary baseline before renderer awaits. Integration baseline is
43f69717f0d04c4b603b4e7edfc42480be2c6d14; this unit depends on input-authority
head a339b8e7f4de612ecfc1038ed2e2d11057990135 (#568). Frozen master stays
15c0fae22f7618e94c82681227057c66011be2a9. Follow #118's publication-admission
contract without claiming filesystem compare-and-swap.

## Interface and flow

ExportService owns an immutable Sendable ExportDestinationAdmission: selected
file URL, opened parent descriptor/identity and absent-or-regular primary stamp
(device/inode, size and modification/change timestamps). It captures protected
source/open-document URLs before rendering. Reject existing symlink/nonregular
targets, same-inode aliases/hard links, and same-parent names that conservatively
compare equal across case/Unicode naming. Missing sources still reserve their
same-parent name. The app also transports FileCore's already observed device/inode
identity as a small ExportProtectedFileIdentity value, so unlinking the source
name cannot hide a retained hard link. This adds no FileCore package dependency. Unexpected protection-inspection errors fail closed.

The ordinary app captures this admission on the same main-actor turn after
panel acceptance, before contribution/parse awaits, including the initiating
source and all current session-controller document URLs. It carries the same
admission through HTML and PDF. Direct service callers get an entry-time
admission; direct prepared-writer tests authorize at their write call. A request
cannot substitute another URL for an admission.

Publication keeps the existing parent-identity gate and descriptor-relative
scratch/verification mechanics. Revalidate the captured parent and primary
before companion staging and immediately before promotion. Absent targets
retain no-replace promotion. Expose a bounded primary-data publication method
on the admission so the existing PDF adapter can use the same boundary after
its validation, instead of path-based replacement. This changes promotion,
not WebKit layout, NSPrintOperation or the fallback's semantics.

## Failure, tests and limits

Changed/created/deleted/replaced primary or parent refuses publication before
touching companions; preserve previous and unrelated files. Source aliases get
a localized choose-another-destination error. Exact input capability and output
admission are separate: neither grants the other's filesystem authority.

Private Foundation/POSIX fixtures cover existing/absent targets across a held
render interval, in-place edits, parent replacement, hard links/symlinks, other
open and missing-document names, Unicode/case conservatism, retarget attempts,
fresh retries and primary-data publication. Hosted app tests prove pre-parse
admission and the same frozen object through ordinary HTML/PDF wiring. Run
source-identical Debug/Release controls, strict lint/format, Compliance,
compile-only local app/tests and complete locked hosted CI before each merge.
Keep first failures. Local app/app-target execution remains held.

This is authorization-time protection of the captured document set, not a
global lock against documents opened later or arbitrary external writers.
Existing-file precheck plus rename remains non-CAS. PDF scratch ownership and
automatic crash repair remain explicit follow-on review/source units. Do not
enable held #519/#520 or SVG commands, change signing/keys/accounts, merge
master or perform public promotion. Final native acceptance and independent
release review remain required.
