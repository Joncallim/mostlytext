# D2 default page occupancy — 19 November 2026

The app's shared D2 renderer previously admitted two offscreen WebKit pages at
once. This change makes its default one page while leaving explicit pool-size
configuration, the five-second evaluation deadline, the 15-second admission
deadline, source limit and SVG output limit intact. The shared pool and the
Graphviz/Mermaid renderers are unchanged.

## Controlled observation

[Release run 44452733760](https://github.com/Joncallim/mostlytext/actions/runs/44452733760)
compared the same two concurrent D2 sources under pool sizes two and one on
one disposable macOS 26 runner. The source hashes, SVG hashes and SVG lengths
matched. From first request to both rendered results, two slots took 5.446 s
and one slot took 3.189 s. The sampler observed two new WebContent processes
at a combined peak 1,489,027,072 bytes with two slots, versus one at
709,459,968 bytes with one slot. These are one-run, sampled same-user helper
figures; helper attribution and unmeasured transients limit the memory claim.
The two-slot process-group peak included numerous Swift driver processes and
must not be reported as D2 memory consumption.

The separate [Release source-budget run 44122298387](https://github.com/Joncallim/mostlytext/actions/runs/44122298387)
rendered a 256-edge chain and 256-edge star within the existing five-second
evaluation budget. Its 512-edge chain was refused by D2's JavaScript layout
stack, which remains an open complexity/diagnostic finding rather than evidence
that a source-byte limit should change.

## Qualification boundary

The product regression checks six queued renders on the new default and keeps
the explicit two-slot concurrent control. A final exact-head Release diagram
selection, normal app build and source checks are required before merge. This
change narrows page occupancy; it does not establish complete #7 memory,
performance, Quick Look or native containment acceptance. The failed static
Mermaid Quick Look attempt is recorded separately on #7.
