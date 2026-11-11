# Lower the final HTML export ceiling after a real Release memory ramp

## Owner summary

Large self-contained HTML exports can repeat the same image bytes many times.
The provisional 256 MiB output limit allowed a near-boundary export that reached
1.39 GiB peak app memory on a disposable macOS 26 Release runner. Lower the
complete HTML output limit to 128 MiB so that case refuses before materializing
the large document. The separate 128 MiB companion resource-payload allowance
and 256 MiB PDF/managed-output recovery bound stay in place. Very large
self-contained documents can use companion assets or split their content.

This is a memory-safety calibration slice of issue #11, not completion of its
whole export/performance or final signed-candidate criteria.

## Measured baseline and decision

Main `055798c29d5b899c3be45fc4c8822f217a5ddcb9` passed exact-source
[Release calibration 42952014094](https://github.com/Joncallim/mostlytext/actions/runs/42952014094)
and all 19 fresh-process cases in
[graduated ramp 42952051573](https://github.com/Joncallim/mostlytext/actions/runs/42952051573)
on macOS 26.7.2 / Xcode 26.6. Both run artifacts were downloaded and their
source hashes, outcomes and owned exits read back. The near-256 MiB case
published 268,431,606 bytes at 1,457,324,032 bytes app peak RSS. Two
approximately 128 MiB cases peaked at 802.6 and 909.2 MiB app RSS. The latter
outputs were 6,914 bytes over 128 MiB due to complete-document markup; the new
near-boundary fixture uses two full 32 MiB images and one slightly smaller
image to land just below 128 MiB.

The lower limit is a fixed complete-document UTF-8 byte ceiling. Both
self-contained and companion HTML still count shell, metadata and body bytes.
The 128 MiB companion *resource* allowance is separate: an output using
companion files need not inline those bytes. HTML that exceeds its final ceiling
returns the existing budget error without publishing an output. Existing
authenticated managed outputs and PDF files up to the former 256 MiB boundary
remain readable and recoverable; reducing the new HTML assembly ceiling must
not silently narrow their retention authority or PDF publication path.

## Verification and remaining gates

- Package tests cover the final writer's byte counting and an older managed
  primary just above 128 MiB (sparse file, no large test allocation), while
  preserving the 256 MiB + 1 refusal.
- The hosted Release ramp now includes a near-128 MiB successful output and
  clean refusals for three full 32 MiB repeats, 96 MiB aggregate resources,
  larger repeats and larger aggregate resources. It retains source, individual
  resource, occurrence and distinct-resource boundaries.
- Exact-head full CI, normal Release and the actual-path ramp must pass before
  this source is merged. Final candidate PDF responsiveness, complete-operation
  cancellation, real menu journey and total memory policy remain separate #11
  acceptance criteria.
