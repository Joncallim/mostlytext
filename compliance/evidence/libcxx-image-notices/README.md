# Complete libc++ and libc++abi root notices from the recorded image

The notice corpus now preserves both C++ runtimes' complete root licences and
referenced partial contributor credits. The actual
[Graphviz link map](../graphviz-link-inputs/README.md) names ten members of
`libc++-noexcept.a` and eight of `libc++abi-noexcept.a`. The selected texts come
from the final filesystem of that recorded compiler image and match the immutable
Emscripten source reference byte for byte. They are conservative root attribution,
with independent per-file/grant and final-retention review still open.

| Complete source text | Bytes | SHA-256 prefix |
|---|---:|---|
| libcxx/LICENSE.TXT | 16,703 | 539dd7aed86e8a4f |
| libcxx/CREDITS.TXT | 4,124 | 054e099bf5954c88 |
| libcxxabi/LICENSE.TXT | 16,706 | e2b35be49f7284a4 |
| libcxxabi/CREDITS.TXT | 1,660 | a259fff28a51623f |

All four files retain their exact original bytes under `compliance/licenses/`.
Both complete root licences include modern Apache/LLVM-exception and legacy
portions; no subsection is substituted or convenient licence elected. The similar
licence texts are distinct and cannot be swapped. Each credits file expressly
describes a partial contributor list; it is retained without an exhaustive-author
claim. Two `kind: attribution` inventory records and regenerated notices/SBOM
carry these texts. All 153 earlier component records are unchanged; there are now
155 records. The runtime/Swift package dependency graph is unchanged.

## Actual image and source correspondence

The [manifest](manifest.json) binds the existing recorded index `4e332f73...`,
Linux AMD64 child `c2ac84c2...`, config `f8b9ec6e...`, all four selected paths and
the exact link-stage member lists. Full raw replay verifies every compressed and
uncompressed layer identity before reading those selected files with the corrected
overlay reader. All four final files come from SDK layer `9fb8c7e6...`; no later
selected-file replacement or whiteout occurs. No image filesystem is applied to
the host, and no image executable is launched.

Separate readback from source-reference commit
`263db4cffa6f9fc2ec514a70abac81362ea41849` matches all four complete files.
The manifest preserves exact source URLs and Git blob identities. This strengthens
these selected text bindings without asserting that every file in the compiler
image has that unique source revision. The earlier image version-marker difference
and original compiler-rt/source/image receipts remain unchanged.

Raw selected/reference files, full qualification and failure/resource logs are
retained at `/Volumes/Fast SSD/CORTANA-Builds/libcxx-image-notices-20261104`.
The initial omission record confirms that every new complete text was absent from
the earlier generated corpus. This correction preserves the selected full texts;
it does not approve a complete corresponding-source offer.

## Offline and raw-image verification

```sh
python3 compliance/tools/verify_libcxx_notices.py
python3 -m unittest compliance.tests.test_libcxx_notices -v
```

Replay the retained exact image graph/layers without execution:

```sh
python3 compliance/tools/verify_libcxx_notices.py --inputs /path/to/viz-compiler-image
```

Ordinary verification downloads nothing. It checks the manifest byte pin, complete
source/text hashes, Git blob identities, original image/link records, exact member
subsets, qualified inventory records and complete generated text. Refusal controls
cover missing/partial/swapped texts, removed exceptions/legacy conditions/credits,
false inventory claims, duplicate records, changed image/source/link provenance,
generated omissions and substituted raw bytes/layers.

The first verifier run expected the source credits' extra terminal newline inside
the generated fence. The existing formatter trims trailing whitespace; all terms
were present and all source-file byte hashes were correct. The coverage check now
uses that existing formatter projection while keeping exact source/text hashes.
The first failure is retained, and the formatter/input text is unchanged.

## Build-resource and release boundary

The generated corpus is 536,721 bytes, below the existing 2 MiB reader limit.
Build/resource qualification uses a locked universal Release **compile only**,
exact source-versus-bundle notice equality, the unchanged Foundation-only
`LicenseNoticesContent` reader, final pins and artifact inventory. No local app,
product CLI, helper, AppKit or WebKit execution is part of this procedure. Complete
hosted Mac source CI and Compliance qualify the final PR source separately.

Neither root notices nor a wasm-ld map establish exhaustive per-file obligations,
final optimized retention, independent rights clearance or native licence-window
acceptance. Existing source-review archives remain dated unapproved snapshots.
Complete source approval, separately authorized publication/anonymous retrieval,
native and exact signed-artifact verification remain open. Runtime bytes, pins,
source-offer states, original evidence and all six strict release failures remain.
