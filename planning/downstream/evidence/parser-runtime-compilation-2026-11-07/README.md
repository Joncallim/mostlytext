# Equivalent combined parser compilation

The candidate changes only the runtime Swift package source list and patch
documentation. It compiles the existing lib.c plus the retained separate
conditional wasm/stdlib.c. Exactly the original13 C implementations remain,
with unchanged headers, compiler defines/standard/optimization flags and MIT
text. All260 defined external C symbols and all23,256 ordered highlight values
agree between actual original and combined normal component builds. Actual
wrapper/grammar sources, metadata, current-source geometry, aliases and64
independent cursor controls remain unchanged. Complete compiler/linker inputs,
source inventories and original/combined/paired outputs are retained.

The original five-run median total is232.540125ms and combined210.33625ms.
The declared paired confirmation gives240.56825ms versus213.219417ms. These are
local component observations, not hosted native, full-app or50ms product passes.
First readback/setup failures (quoted response paths and a copied binary's
non-executable mode) are retained and corrected explicitly; neither was a failed
product assertion or an unchanged native retry.

Runtime3b1fb00f changes only Package.swift and patch notes fromcd96b385;487 other
Git objects including C sources/headers/licences are exact. SwiftTreeSitter76f93e7e
and Neon6074d1a5 change only dependency manifests;102/81 other objects remain exact.
All21 other application pins and every dependency owner remain unchanged. The
actual optimized HighlightingTests target compiles against the new24-pin graph,
including the combined lib.c input. No native app/helper runs in the owner account.

The continuous C probe again completes all324 ordering/ownership pairs in each
of5 phases, the original36,866-visit work failure and candidate2-visit pass, and
identical complete candidate/sanitized output with empty sanitizer stderr. Its
exact source1590-hash/24-pin receipt and all local executable digests are
independently verified against application source39d0de72. These C controls use
the combined entry point in both phases and do not alone establish the Swift
package-build delta. Earlier262-case corpus and6,000-edit trace receipts likewise
remain attached to their original unchanged C source checkpoints.

The rejected sorting comparison is preserved separately: original median query
53.216541ms versus53.760625ms, with identical output but no useful improvement.
No sorting source enters any owner fork or application pin. Bounded sampling
attributes most query work to actual C traversal.

The preceding complete PR1064d7 Release failure503.522292ms>500 is retained in
the external release artifact and PR record. The new graph requires complete
fresh hosted CI, both native configurations and every triggered integration/
mutation check before merge. No assertion, threshold, fixture, fallback8192,
source-offer, signing or owner-native gate changes.
