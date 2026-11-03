# Repeatable export retention scans

## Owner summary

A retention check must inspect the whole directory every time. The existing
helper duplicates the admitted descriptor, which shares its directory position;
a later scan of the same descriptor can silently miss retained files. Give each
scan its own read position while keeping all existing limits and preservation
rules. This is a bounded source correction under MostlyText #11/#17, not the
unfinished companion manifest or automatic cleanup policy.

Baseline: combined recovery/localization source
86ac012f2e1e4e2591787d0736e6aac15af8826a.

## Scope and policy

Change only the retention enumerator to open `.` relative to the admitted
directory with read-only/directory/no-follow/close-on-exec flags, as the private
journal count already does. Close it through `closedir` on every path. Preserve
entry/name/byte ceilings, cancellation, no-adoption/no-deletion behavior and error
handling. No new dependency, public interface, resource budget or native behavior.

## Verification

Use owned temporary directories and the actual non-application source. Repeated
asset scans on one descriptor must report the same complete names and byte count;
a later matching primary scratch must still refuse growth. Capture real failures
on the old code, then run the combined focused Debug/Release controls, strict
lint/pinned format, compile-only locked Release and full hosted checks. Native,
companion inventory, calibration, signing and release acceptance stay open.
