# Immutable query capture-name reuse evidence

Exact production fixture: 1,000,008 UTF-8 bytes, 23,256 ordered highlights.
Original SwiftTreeSitter: 0beea992c4246f93a122de846c8611c9be19aeb7.
Names-only child: f2163a8bc5d0f1ce76b4cead48ce0f3ade4aa9f3.
Manifest-only Neon child: 72174c8de8f28c957fd48850b90de99899b709ee.

Eight alternating process pairs, three measured iterations per process:
initial names-only query medians 69.380 ->57.635 ms; final exact-source
names-only medians 65.572 ->54.727 ms (16.5% query reduction). Final total
medians 237.085 ->225.582 ms (4.9%). Both retain exactly identical ordered
NamedRange JSON. Parse timing variation is not attributed to the cache.
These are local inspected Foundation/C standalone measurements, not a hosted
full-suite or product performance pass. Original 500/400 ms ceilings remain.

Final before/after controls also verify actual named/global directives, duplicate
key last-wins behavior, independent injection depths, current Unicode/CRLF
source offsets while reusing one query and 64 concurrent independent cursors.
They use public APIs, immutable trees and exact output equality. The canonical
three package tests are compiled locally and execute only in hosted macOS 26.

The additional metadata-cache experiment gives no further material query gain
and is not adopted. Its first inaccessible-private-property compile error and
the initial read-only owned-copy preparation failure remain recorded; the
corrected probe uses public tree.copy(). The initial app test-target compilation
omitted -enable-testing and is retained separately; the corrected actual Release
target compiles. Compliance first rejected the changed registered Markdown
manifest digest; that existing inventory record is corrected. No product
assertion, threshold, deadline or fixture is removed or weakened.

The committed harness, unchanged fixture, paired measurements, final source and
license/tree/pin proofs explain the experiment. The original raw capture vectors
and all full logs are retained under the task's parser-query-profile-20261106
build directory. Rebuild the harness as a standalone executable with the pinned
SwiftTreeSitter and the actual vendored Markdown product; for a baseline/candidate
comparison, use an owned Markdown manifest that selects the same dependency
revision as each root. Preserve all grammar/query bytes. Compare all ordered
values and check linked libraries before execution; never launch the owner app
or a native test helper locally. No signing, account gate or release acceptance
is established here.

Preparation is replayable with `python3 prepare.py REPOSITORY NEW_OUTPUT`.
It makes owned grammar copies, preserves every source/resource/license byte,
and changes only each copy's reviewed dependency requirement. It records their
original hashes, phase manifests and two immutable remote pins. Build `probe`
with scratch directory `build`, then `candidate-probe` with `candidate-build`,
using `swift build --package-path PACKAGE --scratch-path SCRATCH -c release
--force-resolved-versions`. Inspect all source inputs and linked libraries before
running `python3 NEW_OUTPUT/measurement.py`; that script refuses GUI linkage,
compares exact ordered values and preserves every measured process result.
This recipe prepares standalone text-only probes, never the owner app or a
native test helper.
